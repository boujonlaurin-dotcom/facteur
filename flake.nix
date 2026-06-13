{
  description = "Facteur — mobile daily digest (Flutter + FastAPI + Postgres)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Flutter pulls in unfree Android tooling on some platforms.
          config.allowUnfree = true;
        };

        # Python 3.12 is mandatory: 3.13+ breaks pydantic
        # (see CLAUDE.md → Contraintes Techniques).
        python = pkgs.python312;
      in
      {
        devShells.default = pkgs.mkShell {
          name = "facteur-dev";

          packages = with pkgs; [
            # ── Python toolchain ────────────────────────────────────────────
            python
            python.pkgs.pip
            python.pkgs.virtualenv
            uv
            ruff

            # ── Mobile toolchain ────────────────────────────────────────────
            flutter

            # ── Node (Railway CLI fallback, MCP servers, tooling) ───────────
            nodejs_22

            # ── Project CLIs (replace the Brewfile / setup-cli-tools.sh) ────
            railway
            supabase-cli
            sentry-cli
            gitleaks

            # ── Build & scripting ───────────────────────────────────────────
            gnumake
            git
            jq
            curl
            bash

            # ── Postgres client (psql against the Dockerized test DB) ───────
            postgresql_16
          ];

          shellHook = ''
            export PROJECT_ROOT="$PWD"
            export PYTHONDONTWRITEBYTECODE=1

            # Expose the API venv (created by `make bootstrap`) on PATH if it exists,
            # so `alembic`, `uvicorn`, `pytest` resolve without sourcing activate.
            if [ -d "$PROJECT_ROOT/packages/api/.venv/bin" ]; then
              export PATH="$PROJECT_ROOT/packages/api/.venv/bin:$PATH"
            fi

            cat <<'EOF'
            ╔══════════════════════════════════════════════════════════════╗
            ║                  Facteur dev shell ready                     ║
            ╚══════════════════════════════════════════════════════════════╝
            EOF
            echo "  Python : $(python --version 2>&1)"
            echo "  Flutter: $(flutter --version 2>/dev/null | head -n1 || echo 'not initialized')"
            echo ""
            echo "Next steps:"
            echo "  make bootstrap   # one-time: venv + deps + test DB + migrations"
            echo "  make doctor      # verify environment health"
            echo "  make api-serve   # run the API on :8080"
            echo "  make test-api    # backend tests"
            echo "  make test-mobile # Flutter tests"
            echo ""
            echo "Note: Docker is required for the test Postgres DB but is NOT"
            echo "provided by this shell. Install it system-wide (e.g. Docker"
            echo "Desktop, OrbStack, or rootless docker on Linux)."
          '';
        };
      });
}
