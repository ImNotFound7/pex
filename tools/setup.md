# Toolchain setup (macOS arm64)

Requires Python 3.14.x (tested 3.14.7; `brew install python@3.14` if absent; 3.12 also expected to work). Versions: see `versions.txt`. OCaml 5.2.1 worked with hardcaml v0.17.0; no fallback needed.
cocotb 2.1.0 installs and imports under system Python 3.14.7; no Homebrew python needed.

```bash
REPO=$PWD   # run this whole block from the repo root
brew install opam
opam init -y --bare --disable-sandboxing
opam switch create pex 5.2.1   # on a fresh machine, skip this and use the import below
eval $(opam env --switch=pex)
# pinned: from the committed export (run from repo root). Original resolution was:
#   opam install -y dune hardcaml hardcaml_waveterm ppx_hardcaml ppx_expect ppx_jane ppx_yojson_conv yojson
opam switch import tools/opam-switch.export --switch pex -y

# OSS CAD Suite 2026-10-25 -> ~/tools/oss-cad-suite (delete tarball after extracting)
mkdir -p ~/tools/dl && cd ~/tools/dl
curl -LO https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-10-25/oss-cad-suite-darwin-arm64-20261025.tgz
tar xzf oss-cad-suite-darwin-arm64-20261025.tgz -C ~/tools && cd ~ && rm -rf ~/tools/dl
source ~/tools/oss-cad-suite/environment

cd "$REPO"
python3 -m venv .venv
.venv/bin/pip install cocotb==2.1.0 pytest==9.1.1
```

Every new shell: `eval $(opam env --switch=pex); source ~/tools/oss-cad-suite/environment`.

Verify:
```bash
ocaml -version; opam list hardcaml; iverilog -V | head -1; verilator --version; yosys -V; sby --help | head -1; .venv/bin/python -c "import cocotb; print(cocotb.__version__)"
```
Notes: `iverilog -V` also prints "Unable to get version" lines to stderr; compile+run smoke test (iverilog + vvp) works. `--disable-sandboxing` is used because opam macOS sandbox is unavailable non-interactively.
