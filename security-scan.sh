#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------
#  Directories and Configurations
# ------------------------------------------------
BASE_DIR="$(pwd)"
REPOS_DIR="${BASE_DIR}/repos"
RESULTS_DIR="${BASE_DIR}/results"
LOGS_DIR="${BASE_DIR}/logs"
CONFIG_FILE="${BASE_DIR}/config/repos.txt"

mkdir -p "$REPOS_DIR" "$RESULTS_DIR" "$LOGS_DIR"


config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "Config file not found. Creating sample config at $CONFIG_FILE"
        cat > "$CONFIG_FILE" << 'EOF'
# Add your Github repository URLs here (one per line)
EOF
        log "Sample  config created"
        log "Edit $CONFIG_FILE to add your repositories"
    fi
}



# ------------------------------------------------
# Utility Functions
# ------------------------------------------------
log_file="$LOGS_DIR/audit_$(date +%F_%H-%M-%S).log"
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$log_file"
}

save_results() {
    local scanner="$1"
    local repo_name="$2"
    local outfile="${RESULTS_DIR}/${scanner}_${repo_name}.txt"
    cat > "$outfile"
}

extract_repo_name() {
    # extracts "repo" from:  https://github.com/user/repo.git
    local url="$1"
    basename -s .git "$url"
}

# ------------------------------------------------
# Repo Management
# ------------------------------------------------
clone_or_update_repo() {
    local repo_url="$1"
    local repo_name
    repo_name=$(extract_repo_name "$repo_url")
    local repo_path="$REPOS_DIR/$repo_name"
    
    if [[ -d "$repo_path/.git" ]]; then
        log "Updating repo: $repo_name"
        git -C "$repo_path" pull --quiet 2>&1 || log "Failed to update $repo_name"
    else
        log "Cloning repo: $repo_name"
        git clone "$repo_url" "$repo_path" --quiet 2>&1 || log "Failed to clone $repo_name"
    fi
}

# ------------------------------------------------
# Scanners
# ------------------------------------------------
run_trufflehog() {
    local repo_url="$1"
    local repo_name
    repo_name=$(extract_repo_name "$repo_url")
    local repo_path="$REPOS_DIR/$repo_name"

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log "Skipping TruffleHog: Docker not installed"
        return
    fi

    log "Running TruffleHog on $repo_name"

    sudo docker run --rm \
        -v "$repo_path:/scan" \
        trufflesecurity/trufflehog:latest filesystem /scan \
        2>&1 | save_results "trufflehog" "$repo_name"
}

run_gitleaks() {
    local repo_url="$1"
    local repo_name
    repo_name=$(extract_repo_name "$repo_url")
    local repo_path="$REPOS_DIR/$repo_name"

    if ! command -v gitleaks &> /dev/null; then
        log "Skipping Gitleaks: not installed"
        return
    fi

    log "Running Gitleaks on $repo_name"
    
    # Run gitleaks and save output
    gitleaks detect \
        --source "$repo_path" \
        --verbose \
        --no-git \
        2>&1 | save_results "gitleaks" "$repo_name"
    
    # Also generate JSON report
    gitleaks detect \
        --source "$repo_path" \
        --report-path "${RESULTS_DIR}/gitleaks_${repo_name}.json" \
        --no-git \
        2>&1 > /dev/null || true
}

run_ggshield() {
    local repo_url="$1"
    local repo_name
    repo_name=$(extract_repo_name "$repo_url")
    local repo_path="$REPOS_DIR/$repo_name"

    if ! command -v ggshield &> /dev/null; then
        log "Skipping GitGuardian: not installed"
        return
    fi

    log "Running GitGuardian on $repo_name"
    ggshield secret scan repo "$repo_path" --no-tty \
        2>&1 | save_results "ggshield" "$repo_name"
}

run_manual_checks() {
    local repo_url="$1"
    local repo_name
    repo_name=$(extract_repo_name "$repo_url")
    local repo_path="$REPOS_DIR/$repo_name"

    log "Running manual checks on $repo_name"

    {
        echo "================================================================="
        echo "Manual Security Checks for: $repo_name"
        echo "================================================================="
        echo "Scan Date: $(date)"
        echo ""
        
        echo "=== 1. Environment Files ==="
        find "$repo_path" -type f -name "*.env*" -not -path "*/.git/*" 2>/dev/null || echo "✓ No .env files found"
        echo ""
        
        echo "=== 2. Private Keys ==="
        find "$repo_path" -type f \( -name "*.pem" -o -name "*.key" -o -name "*.p12" \) -not -path "*/.git/*" 2>/dev/null || echo "✓ No private key files found"
        echo ""
        
        echo "=== 3. Password/Secret Patterns ==="
        grep -RniE "password|secret|api_key|apikey|token" "$repo_path" \
            --exclude-dir=.git \
            --exclude-dir=node_modules \
            --exclude="*.md" \
            2>/dev/null || echo "✓ No suspicious patterns found"
        echo ""
        
        echo "=== 4. Hardcoded IPs ==="
        grep -RnE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" "$repo_path" \
            --exclude-dir=.git \
            --exclude-dir=node_modules \
            2>/dev/null | grep -v "127.0.0.1\|0.0.0.0" || echo "✓ No hardcoded IPs found"
        echo ""
        
        echo "=== 5. AWS Credentials ==="
        grep -RniE "AKIA[0-9A-Z]{16}|aws_access_key_id|aws_secret_access_key" "$repo_path" \
            --exclude-dir=.git \
            2>/dev/null || echo "✓ No AWS credentials found"
        echo ""
        
        echo "=== 6. Database Connection Strings ==="
        grep -RniE "mysql://|postgres://|mongodb://|redis://" "$repo_path" \
            --exclude-dir=.git \
            --exclude="*.md" \
            2>/dev/null || echo "✓ No database connections found"
        echo ""
        
        echo "=== 7. Git History - Deleted Sensitive Files ==="
        git -C "$repo_path" log --diff-filter=D --summary --all 2>/dev/null | \
            grep -E "\.(env|key|pem|p12|pfx|crt)$" || echo "✓ No sensitive files in history"
        echo ""
        
        echo "================================================================="
        
    } | save_results "manual_checks" "$repo_name"
}

generate_summary() {
    log "Generating summary report"
    
    local summary_file="${RESULTS_DIR}/00_SUMMARY.txt"
    
    {
        echo "================================================================="
        echo "SECURITY AUDIT SUMMARY REPORT"
        echo "================================================================="
        echo "Generated: $(date)"
        echo "Results Directory: $RESULTS_DIR"
        echo "================================================================="
        echo ""
        
        for result_file in "$RESULTS_DIR"/*.txt; do
            if [[ -f "$result_file" && ! "$result_file" =~ 00_SUMMARY ]]; then
                local filename=$(basename "$result_file")
                local filesize=$(wc -l < "$result_file")
                
                echo "📄 $filename ($filesize lines)"
                
                # Show first few lines if file has content
                if [[ $filesize -gt 5 ]]; then
                    echo "   Preview:"
                    head -n 3 "$result_file" | sed 's/^/   | /'
                    echo "   ..."
                fi
                echo ""
            fi
        done
        
        echo "================================================================="
        echo "Next Steps:"
        echo "  1. Review each report in: $RESULTS_DIR"
        echo "  2. Investigate any findings marked with ⚠"
        echo "  3. Rotate any exposed credentials immediately"
        echo "  4. Update .gitignore to prevent future leaks"
        echo "================================================================="
        
    } | tee "$summary_file"
}

# ------------------------------------------------
# Main Loop
# ------------------------------------------------
main() {
    log "Starting security audit"
    log "Configuration: $CONFIG_FILE"
    
    # Read repos from config file
    mapfile -t REPO_URLS < "$CONFIG_FILE"
    
    if [[ ${#REPO_URLS[@]} -eq 0 ]]; then
        log "ERROR: No repositories found in $CONFIG_FILE"
        exit 1
    fi
    
    log "Found ${#REPO_URLS[@]} repositories to scan"
    echo ""
    
    for repo_url in "${REPO_URLS[@]}"; do
        # Skip empty lines and comments
        [[ -z "$repo_url" || "$repo_url" =~ ^# ]] && continue
        
        repo_name=$(extract_repo_name "$repo_url")
        log "================================"
        log "Processing: $repo_name"
        log "================================"
        
        clone_or_update_repo "$repo_url"
        run_trufflehog "$repo_url"
        run_gitleaks "$repo_url"
        run_ggshield "$repo_url"
        run_manual_checks "$repo_url"
        
        log "✓ Finished processing $repo_name"
        echo ""
    done
    
   # ------------------------------------------------
    # Findings Summary and Exit
    # ------------------------------------------------
    local findings=0

    for result_file in "$RESULTS_DIR"/*.txt; do
        [[ ! -f "$result_file" ]] && continue
        if grep -qi "Found unverified result" "$result_file" || \
        grep -qi "\"verified_secrets\": [1-9]" "$result_file"; then
            log "⚠ Findings detected in $(basename "$result_file")"
            findings=$((findings+1))
        fi
    done

    if [[ $findings -gt 0 ]]; then
        log "⚠ $findings repositories contain potential secrets — failing pipeline"
        exit 1
    else
        log "✓ No secrets detected — pipeline passes"
        exit 0
    fi

}


# Run the main function
main "$@"