# Vendored dependencies

All dependencies are ordinary source files under `lib/`. Builds and tests require no dependency downloads, submodules, environment variables, RPC, FFI, or filesystem cheatcode permissions.

| Dependency | Version | Upstream | Included |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.0.2 | https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2 | ERC20, SafeERC20, ReentrancyGuard and their transitive imports; MIT license |
| forge-std | v1.9.7 | https://github.com/foundry-rs/forge-std/tree/v1.9.7 | `src/`, MIT and Apache licenses; tests only |

The source files are unmodified upstream copies. The SHA-256 hashes of the upstream tag archives fetched from GitHub's codeload endpoint are:

- OpenZeppelin: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`
- forge-std: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`

Compiler: Solidity 0.8.26, pinned in `foundry.toml`; the verification environment supplies the compiler. No compiler binary is vendored.
