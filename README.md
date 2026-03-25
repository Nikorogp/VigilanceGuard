# VigilanceGuard: AI-Driven Market Manipulation Detection

## Introduction
VigilanceGuard is a sophisticated Clarity smart contract designed to bridge the gap between off-chain artificial intelligence and on-chain decentralized finance (DeFi) security. As market manipulation tactics—such as wash trading, spoofing, and flash-loan-assisted front-running—become increasingly complex, static rule-based systems often fail to protect users. 

This protocol serves as an **automated enforcement layer**. It allows high-fidelity AI oracles to feed real-time manipulation risk scores directly into the Stacks blockchain. Depending on the severity of the detected threat, the contract can autonomously trigger defensive measures ranging from account flagging and fee escalations to a protocol-wide circuit breaker.



---

## Table of Contents
* 1. Overview
* 2. Key Features
* 3. System Architecture
* 4. Technical Specifications
* 5. Internal Private Functions
* 6. Public Interface (External API)
* 7. Read-Only Data Access
* 8. Security and Slashing Mechanics
* 9. Mitigation Strategies
* 10. Installation and Deployment
* 11. Contributing Guidelines
* 12. MIT License

---

## Overview
VigilanceGuard operates on the principle of **Incentivized Truth**. By requiring AI oracles to stake STX tokens, the protocol ensures that reporting is backed by economic collateral. The contract categorizes market behavior into four distinct risk tiers, allowing for a nuanced response that protects the ecosystem without unfairly penalizing legitimate high-volume traders.

## Key Features
* **AI Oracle Consensus:** Integration with off-chain models that analyze deep liquidity patterns.
* **Dynamic Risk Scoring:** Real-time calculation of risk based on volume, frequency, and attack vectors.
* **Multi-Tiered Mitigation:** Responses ranging from "Low" (Warning) to "Critical" (Liquidation & Global Pause).
* **Oracle Staking & Slashing:** A robust security model to prevent oracle collusion or false reporting.
* **On-Chain Appeal System:** Transparency for users to contest flags by providing cryptographic evidence.
* **Circuit Breaker:** An emergency halt mechanism for extreme market volatility or systemic attacks.

---

## System Architecture
The contract acts as a central hub for three primary actors:
1.  **Contract Owner:** Manages the registry of authorized AI oracles and resolves user appeals.
2.  **AI Oracles:** Submit high-dimensional market data and stake tokens to guarantee honesty.
3.  **Users:** The subjects of monitoring who can appeal flags if they believe the AI has produced a false positive.



---

## Technical Specifications

### Constants and Error Codes
The contract utilizes a strictly defined set of error codes to ensure debugging is straightforward and state transitions are atomic.

| Error Code | Constant | Description |
| :--- | :--- | :--- |
| u100 | `err-owner-only` | Action restricted to the contract administrator. |
| u101 | `err-unauthorized-oracle` | The caller is not a registered AI oracle. |
| u103 | `err-trading-paused` | Action blocked by the active circuit breaker. |
| u104 | `err-insufficient-stake` | Oracle has not locked the minimum 50 STX. |
| u109 | `err-oracle-slashed` | Oracle has been blacklisted for malicious data. |

### Risk Tiers
* **Tier Low (u1):** Informational flag; no protocol restriction.
* **Tier Medium (u2):** Temporary fee multipliers and increased monitoring.
* **Tier High (u3):** Forced cooldowns and cancellation of open orders.
* **Tier Critical (u4):** Immediate account liquidation and protocol-wide pause.

---

## Internal Private Functions
These functions are the "brains" of the contract, handling the logic that is not directly accessible by external users.

* **`is-oracle`**: Validates if a principal is in the `authorized-oracles` map and has not been slashed.
* **`has-sufficient-stake`**: Checks the `oracle-stakes` map to ensure the principal meets the `min-oracle-stake` threshold.
* **`is-valid-score`**: A boundary check ensuring all risk inputs are within the $0 \dots 100$ range.
* **`calculate-risk-tier`**: Logic gate that converts a raw `uint` score into a categorized risk tier (1-4).

---

## Public Interface (External API)

### Administrative Functions
* **`add-oracle (principal)`**: Adds a new AI entity to the whitelist.
* **`remove-oracle (principal)`**: Revokes an entity's ability to report.
* **`slash-malicious-oracle (principal)`**: Executed by the owner if an oracle is caught reporting false positives. It zeros out the stake and blacklists the entity.

### Oracle Operations
* **`stake-as-oracle (uint)`**: Allows an authorized oracle to deposit the required 50 STX (or more) to activate their reporting status.
* **`report-manipulation (principal, uint)`**: The primary entry point for standard AI reporting.
* **`process-ai-consensus-flag`**: An advanced function taking multiple parameters:
    * `base-score`: The initial AI confidence.
    * `volume-multiplier`: Impact of the trade size.
    * `frequency-multiplier`: Impact of trade velocity.
    * `is-flash-loan-involved`: A boolean that adds a flat $+20$ penalty to the score.

### User Functions
* **`submit-appeal (buff 32)`**: Allows a flagged user to submit a hash of evidence (stored off-chain on IPFS) to prove their innocence.

---

## Read-Only Data Access
These functions allow off-chain UI and other contracts to query the state of VigilanceGuard without consuming gas.

* **`get-flag-data (target principal)`**: Returns the current score, tier, and active status of an account.
* **`get-oracle-stake (oracle principal)`**: Returns the total STX locked by a specific oracle.
* **`get-protocol-status`**: Returns the state of the circuit breaker (true/false).
* **`get-appeal-details (user principal)`**: Provides the status and evidence hash of a pending appeal.

---

## Mitigation Strategies
The `execute-advanced-mitigation-strategy` function is the enforcement arm. It calculates the time passed since the flag (in blocks) and applies the following logic:

1.  **Critical Mitigation:** If the tier is Critical, it sets `is-trading-paused` to `true`, effectively halting the entire protocol to prevent a liquidity drain.
2.  **High Mitigation:** Triggers a cooldown. In a production environment, this would interface with a DEX to cancel that user's limit orders.
3.  **Medium Mitigation:** Checks if the flag occurred within the last 144 blocks ($\approx 24$ hours). if so, it signals the protocol to apply a fee penalty.

---

## Contributing Guidelines
We welcome contributions to VigilanceGuard! Please follow these steps:
1.  Fork the repository.
2.  Create a feature branch (`git checkout -b feature/SmartMitigation`).
3.  Ensure all Clarity traits are implemented.
4.  Submit a Pull Request with a detailed description of changes.
5.  All code must pass the `clarinet check` and include unit tests in the `tests/` directory.

---

## MIT License

Copyright (c) 2026 VigilanceGuard Protocol

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

