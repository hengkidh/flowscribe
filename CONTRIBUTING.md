# Contributing

Thank you for helping. Please read this first: skills are instructions that AI agents follow in other
people's projects, so they are reviewed like executable code.

## Rules for every change

1. **Run the tests**: `bash tests/install.test.sh`. CI also runs ShellCheck and validates the examples
   against the schemas.
2. **Skills, `payload/agents-block.md` and `install.sh` are security-sensitive.** In a pull request that
   changes them:
   - no instruction may make an agent run commands, fetch URLs, install software or send data without
     asking the user;
   - no instruction may weaken the security rules in `payload/agents-block.md`;
   - no hidden text: no HTML comments with instructions, zero-width characters, base64 or other encodings;
   - explain in the PR description why each instruction is needed.
3. **The installer stays boring**: bash 3.2 compatible, no network, no `eval`, no new external commands
   beyond POSIX tools and `shasum`/`sha256sum`. Every new behaviour gets a test, including the case
   where it must refuse.
4. **Schema changes** follow the versioning rules in `spec/contract.md` §10. Breaking changes need a new
   major contract version.
5. **No real data** in examples, tests or screenshots: no client names, hosts, keys or personal data.

## Pull requests

- One topic per PR, with a short description of what and why.
- Commits must be signed. Maintainers merge only after review and green CI.
- Security issues go through [SECURITY.md](SECURITY.md), never a public PR or issue.
