# Testing GridVault (Foundry)

These tests use Foundry (forge). They validate deterministic estimate logic and basic position flows.

Prerequisites
- Install Foundry: https://book.getfoundry.sh/getting-started/installation

Run tests
```bash
forge test
```

Notes
- Tests import `forge-std/Test.sol` and assume Foundry will fetch dependencies via `git` or `lib` config.
- If you prefer JavaScript/Hardhat tests instead, I can add those.
