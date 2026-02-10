# Security Audit Automation Tool

This project provides an automated workflow for scanning multiple GitHub repositories for secrets and sensitive information. It integrates several industry‑standard tools, including TruffleHog (Docker-based), Gitleaks, GitGuardian (optional), and custom manual checks. The script is designed to be simple to run, easy to extend, and suitable for both personal and team use.

---

## Overview

The tool performs the following actions for each repository listed in `config/repos.txt`:

1. Clone or update the repository locally.
2. Run TruffleHog (v3, via Docker) against the repository.
3. Run Gitleaks if installed.
4. Run GitGuardian CLI (optional).
5. Perform manual checks for common secret patterns and sensitive files.
6. Save all results to the `results/` directory.

The script is modular and can be extended with additional scanners or checks as needed.

---

## Project Structure

Security-audit/
│
├── security-scan.sh          # Main script
├── config/
│   └── repos.txt             # List of repositories to scan
├── results/                  # Scan output (ignored by Git)
├── logs/                     # Optional logs (ignored by Git)
├── scripts/
│   └── install-tools.sh      # Optional helper for installing dependencies
├── README.md
├── LICENSE
└── .gitignore


---

## Requirements

- Bash (Linux or macOS)
- Git
- Docker (required for TruffleHog v3)
- Optional:
  - Gitleaks
  - GitGuardian CLI (`ggshield`)

---

## Configuration

Edit `config/repos.txt` to specify the repositories you want to scan.  
Each line should contain a repository name under your GitHub account:


The script assumes repositories are located at:
https://github.com/<your-username>/<repo>.git

---

## Usage

Run the main script:
    $bash security-scan.sh

Results will be written to:
    results/<scanner>_<repository>.txt

---

## Extending the Tool

The script is structured so that each scanner is implemented as a separate function.  
To add a new scanner:

1. Create a new function in `security-scan.sh`.
2. Call the function inside the main repository loop.
3. Save output to the `results/` directory using the existing naming pattern.

This approach keeps the script maintainable and easy to expand.

---

## Limitations

- TruffleHog v3 must be run via Docker unless installed manually.
- The script assumes all repositories belong to the same GitHub user unless modified.
- Results are not aggregated; each scanner writes its own output file.

---

## License

This project is released under the MIT License. See `LICENSE` for details.


