# Stablecoin Project

A decentralized, overcollateralized stablecoin built with Foundry. Users deposit crypto collateral and mint a USD-pegged token against it, with on-chain liquidation keeping the system solvent.

## Overview

- **Collateral:** exogenous crypto assets (such as WETH and WBTC)
- **Peg:** 1 token = 1 USD, enforced by overcollateralization and Chainlink price feeds
- **Minting:** algorithmic, with no governance and no fees
- **Safety:** positions that fall below the minimum health factor can be liquidated by anyone for a bonus

## Stack

- Solidity
- Foundry (forge, anvil, cast)
- OpenZeppelin Contracts
- Chainlink price feeds

## Project Structure

```
src/
  DecentralisedStableCoin.sol   ERC20 stablecoin token (owned by the engine)
  DSCEngine.sol                 Collateral, minting, redemption and liquidation logic
  lib/OracleLib.sol             Stale price check for Chainlink feeds
test/
  fuzz/
    Handler.t.sol               Guided inputs for invariant testing
    OpenInvariantsTest.t.sol    Open invariant tests
  mocks/                        Mock price feeds for local testing
lib/                            External dependencies
```

## How It Works

1. **Deposit** an approved collateral token into `DSCEngine`.
2. **Mint** stablecoin up to the limit allowed by your collateral value.
3. **Burn** stablecoin and **redeem** collateral to exit a position.
4. **Liquidate** any user whose health factor drops below 1 by repaying their debt and receiving their collateral plus a bonus.

The system must always hold more collateral value than stablecoin supply. If a price feed goes stale (no update for 3 hours), `OracleLib` reverts and the engine freezes rather than act on bad data.

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Install

```
git clone <your-repo-url>
cd stablecoin
forge install
```

### Build

```
forge build
```

## Testing

Run the full suite:

```
forge test
```

Useful variations:

```
forge test -vvvv                          # full traces
forge test --match-test <testName>        # a single test
forge test --match-contract <Contract>    # a single contract
forge test --fuzz-runs 1000               # more fuzz iterations
forge coverage                            # coverage report
forge snapshot                            # gas snapshot
```

The suite covers unit tests, fuzz tests, and invariant tests. The core invariant is that total collateral value always exceeds total stablecoin supply.

## Local Deployment

Start a local node in one terminal:

```
anvil
```

Deploy from another, using one of anvil's default private keys:

```
forge script script/DeployDSC.s.sol --rpc-url http://127.0.0.1:8545 --private-key <ANVIL_PRIVATE_KEY> --broadcast
```

## Formatting

```
forge fmt
```

## License

MIT
