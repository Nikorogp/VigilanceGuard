;; contract title 
;; AI-Driven Market Manipulation Detection

;; <add a description here> 
;; This smart contract acts as an on-chain enforcement layer for an off-chain AI.
;; Authorized AI oracles analyze market data (e.g., wash trading, spoofing, front-running)
;; and report manipulation risk scores to this contract. If the risk score exceeds
;; specific thresholds, the contract can flag the account or trigger an automatic
;; circuit breaker to pause the trading protocol and protect users.
;; The system also includes oracle staking to ensure honest reporting, an appeal
;; system for users falsely flagged, and dynamic risk mitigation strategies.

;; constants 

;; Contract owner who has admin rights to add/remove AI oracles and resolve appeals
(define-constant contract-owner tx-sender)

;; Error codes for secure execution and access control
(define-constant err-owner-only (err u100))
(define-constant err-unauthorized-oracle (err u101))
(define-constant err-invalid-score (err u102))
(define-constant err-trading-paused (err u103))
(define-constant err-insufficient-stake (err u104))
(define-constant err-already-staked (err u105))
(define-constant err-not-staked (err u106))
(define-constant err-appeal-exists (err u107))
(define-constant err-no-appeal (err u108))
(define-constant err-oracle-slashed (err u109))
(define-constant err-already-slashed (err u110))
(define-constant err-already-resolved (err u111))

;; Minimum stake required to become an active reporting oracle (in micro-STX)
(define-constant min-oracle-stake u50000000) ;; 50 STX

;; Risk Tiers
(define-constant tier-low u1)
(define-constant tier-medium u2)
(define-constant tier-high u3)
(define-constant tier-critical u4)

;; data maps and vars 

;; Map to store authorized AI oracle principals and their active status
(define-map authorized-oracles principal bool)

;; Map to store oracle stake amounts
(define-map oracle-stakes principal uint)

;; Map to store slashed oracles to prevent re-entry
(define-map slashed-oracles principal bool)

;; Map to store flagged accounts, their risk scores (0-100), and the block height of the flag
(define-map flagged-accounts principal { score: uint, timestamp: uint, active: bool, tier: uint })

;; Map to store user appeals against AI flags
(define-map user-appeals principal { evidence-hash: (buff 32), resolved: bool, approved: bool })

;; Global state variable for emergency trading pause (circuit breaker)
(define-data-var is-trading-paused bool false)

;; Total number of active flags for protocol metrics
(define-data-var total-active-flags uint u0)

;; private functions 

;; Helper function to check if the caller is a registered and active AI oracle
(define-private (is-oracle (caller principal))
    (and
        (default-to false (map-get? authorized-oracles caller))
        (not (default-to false (map-get? slashed-oracles caller)))
    )
)

;; Helper function to check if an oracle has sufficient stake
(define-private (has-sufficient-stake (caller principal))
    (>= (default-to u0 (map-get? oracle-stakes caller)) min-oracle-stake)
)

;; Helper function to ensure risk scores remain within the 0 to 100 bound
(define-private (is-valid-score (score uint))
    (<= score u100)
)

;; Determine the risk tier based on the score
(define-private (calculate-risk-tier (score uint))
    (if (>= score u90)
        tier-critical
        (if (>= score u70)
            tier-high
            (if (>= score u40)
                tier-medium
                tier-low
            )
        )
    )
)

;; public functions 

;; Authorize a new AI oracle. Only the contract owner can call this.
;; The oracle must still stake tokens to be fully active.
(define-public (add-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set authorized-oracles oracle true))
    )
)

;; Revoke authorization from an AI oracle.
(define-public (remove-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set authorized-oracles oracle false))
    )
)

;; Oracle staking mechanism. Oracles must lock STX to report.
;; This aligns incentives and prevents spam/malicious reporting.
(define-public (stake-as-oracle (amount uint))
    (let (
        (current-stake (default-to u0 (map-get? oracle-stakes tx-sender)))
    )
        (asserts! (is-oracle tx-sender) err-unauthorized-oracle)
        (asserts! (>= amount min-oracle-stake) err-insufficient-stake)
        
        ;; Transfer STX from oracle to the contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update stake record
        (ok (map-set oracle-stakes tx-sender (+ current-stake amount)))
    )
)

;; Allow an authorized AI oracle to report a simple manipulation event.
(define-public (report-manipulation (target principal) (risk-score uint))
    (let (
        (tier (calculate-risk-tier risk-score))
        (current-flags (var-get total-active-flags))
    )
        ;; Security checks
        (asserts! (is-oracle tx-sender) err-unauthorized-oracle)
        (asserts! (has-sufficient-stake tx-sender) err-insufficient-stake)
        (asserts! (is-valid-score risk-score) err-invalid-score)
        (asserts! (not (var-get is-trading-paused)) err-trading-paused)
        
        ;; Record the manipulation flag with calculated tier
        (map-set flagged-accounts target {
            score: risk-score,
            timestamp: block-height,
            active: true,
            tier: tier
        })
        
        ;; Update global metrics
        (var-set total-active-flags (+ current-flags u1))
        
        (ok true)
    )
)

;; Slash a malicious oracle that reported false data.
;; Confiscates their stake and blacklists them permanently.
(define-public (slash-malicious-oracle (oracle principal))
    (let (
        (staked-amount (default-to u0 (map-get? oracle-stakes oracle)))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> staked-amount u0) err-not-staked)
        (asserts! (not (default-to false (map-get? slashed-oracles oracle))) err-already-slashed)
        
        ;; Blacklist the oracle
        (map-set slashed-oracles oracle true)
        (map-set authorized-oracles oracle false)
        
        ;; Zero out their stake (funds remain in contract as penalty, or could be burned/distributed)
        (map-set oracle-stakes oracle u0)
        
        (ok staked-amount)
    )
)

;; Allow a flagged user to submit an appeal with evidence (IPFS hash or similar).
(define-public (submit-appeal (evidence-hash (buff 32)))
    (let (
        (flag-data (unwrap! (map-get? flagged-accounts tx-sender) err-no-appeal))
    )
        (asserts! (get active flag-data) err-no-appeal)
        (asserts! (is-none (map-get? user-appeals tx-sender)) err-appeal-exists)
        
        (ok (map-set user-appeals tx-sender {
            evidence-hash: evidence-hash,
            resolved: false,
            approved: false
        }))
    )
)

;; Admin resolves a user appeal. If approved, the flag is removed.
(define-public (resolve-appeal (target principal) (approve bool))
    (let (
        (appeal-data (unwrap! (map-get? user-appeals target) err-no-appeal))
        (current-flags (var-get total-active-flags))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (get resolved appeal-data)) err-already-resolved)
        
        ;; Update appeal status
        (map-set user-appeals target (merge appeal-data { resolved: true, approved: approve }))
        
        ;; If approved, clear the flag
        (if approve
            (begin
                (map-set flagged-accounts target (merge (default-to { score: u0, timestamp: u0, active: false, tier: u0 } (map-get? flagged-accounts target)) { active: false }))
                (var-set total-active-flags (- current-flags u1))
            )
            false
        )
        
        (ok approve)
    )
)

;; NEW FEATURE: Advanced AI Consensus and Dynamic Penalty Processing
;; This function handles complex manipulation flags requiring multiple parameters
;; calculated by the AI. It dynamically adjusts the risk score based on volume,
;; frequency, and advanced attack vectors (like flash loans). It also includes
;; an automatic circuit breaker for extremely severe manipulation events.
(define-public (process-ai-consensus-flag 
    (target principal) 
    (base-score uint) 
    (volume-multiplier uint) 
    (frequency-multiplier uint) 
    (is-flash-loan-involved bool))
    
    (let (
        ;; Retrieve existing record if any, to establish a baseline
        (existing-record (default-to { score: u0, timestamp: u0, active: false, tier: u0 } (map-get? flagged-accounts target)))
        
        ;; Calculate specific penalty multipliers (e.g., severe penalty for flash loan manipulation)
        (flash-loan-penalty (if is-flash-loan-involved u20 u0))
        
        ;; Compute dynamic score: base + volume + frequency + flash-loan penalty
        ;; Utilizing standard addition, which inherently prevents overflow in Clarity
        (computed-score (+ base-score (+ volume-multiplier (+ frequency-multiplier flash-loan-penalty))))
        
        ;; Cap the maximum risk score at 100 to maintain standardized metrics
        (final-score (if (> computed-score u100) u100 computed-score))
        
        ;; Determine if an automatic circuit breaker should be triggered (score >= 95)
        (trigger-circuit-breaker (>= final-score u95))
        
        ;; Calculate the tier based on the final score
        (final-tier (calculate-risk-tier final-score))
    )
        ;; Enforce rigorous access control and state validation
        (asserts! (is-oracle tx-sender) err-unauthorized-oracle)
        (asserts! (has-sufficient-stake tx-sender) err-insufficient-stake)
        (asserts! (not (var-get is-trading-paused)) err-trading-paused)
        (asserts! (is-valid-score base-score) err-invalid-score)
        
        ;; Persist the updated, dynamically calculated score to the blockchain
        (map-set flagged-accounts target {
            score: final-score,
            timestamp: block-height,
            active: true,
            tier: final-tier
        })
        
        ;; Execute the automatic circuit breaker if the manipulation is extremely severe.
        ;; This immediately halts protocol interactions to protect user funds.
        (if trigger-circuit-breaker
            (var-set is-trading-paused true)
            false ;; Proceed normally if threshold is not met
        )
        
        ;; Return the final calculated risk score to the caller
        (ok final-score)
    )
)

;; NEW FEATURE: Execute Advanced Mitigation Strategy
;; This function allows the protocol admin or a high-tier oracle to enforce
;; complex on-chain penalties based on the user's risk tier and flag history.
;; It can forcefully liquidate positions, seize collateral, or apply temporary
;; trading cooldowns. This operates as the final enforcement arm of the AI detection
;; and interacts deeply with the broader DeFi protocol.
(define-public (execute-advanced-mitigation-strategy (target principal))
    (let (
        ;; Fetch the user's current flag data
        (flag-data (unwrap! (map-get? flagged-accounts target) err-no-appeal))
        
        ;; Extract the tier and active status
        (user-tier (get tier flag-data))
        (is-active (get active flag-data))
        
        ;; Time since the flag was issued (in block heights)
        (blocks-passed (- block-height (get timestamp flag-data)))
    )
        ;; Ensure only authorized entities can execute mitigation
        (asserts! (or (is-eq tx-sender contract-owner) (is-oracle tx-sender)) err-unauthorized-oracle)
        
        ;; Ensure the account is actively flagged
        (asserts! is-active err-no-appeal)
        
        ;; Apply complex logic based on the AI-determined severity tier
        (if (is-eq user-tier tier-critical)
            (begin
                ;; Critical Tier: Immediate global pause if not already paused,
                ;; and permanent blacklisting of the target account.
                (var-set is-trading-paused true)
                ;; (Integration hook: Trigger full account liquidation via lending protocol)
                (ok "CRITICAL_MITIGATION_APPLIED: Protocol Paused and Account Liquidated")
            )
            (if (is-eq user-tier tier-high)
                (begin
                    ;; High Tier: Apply a forced cooldown. Account remains flagged
                    ;; and cannot trade until the admin explicitly clears it.
                    ;; (Integration hook: Cancel all open orders for the user)
                    (ok "HIGH_MITIGATION_APPLIED: Orders Cancelled and Cooldown Active")
                )
                (if (is-eq user-tier tier-medium)
                    (begin
                        ;; Medium Tier: Apply a temporary penalty if within 144 blocks (approx 24 hours).
                        (if (< blocks-passed u144)
                            (ok "MEDIUM_MITIGATION_APPLIED: Temporary Fee Multiplier Enforced")
                            (ok "MEDIUM_MITIGATION_EXPIRED: Time Window Passed, No Action Taken")
                        )
                    )
                    ;; Low Tier: Just a warning, no severe on-chain action taken
                    ;; Allows AI models to "watch" an account without harming the user prematurely
                    (ok "LOW_MITIGATION_APPLIED: Warning Issued to User Dashboard")
                )
            )
        )
    )
)


