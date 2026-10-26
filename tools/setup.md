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

## Running the cocotb tests locally

OSS CAD Suite's `vvp` wrapper forces the suite's own Python, so a plain `make` silently uses its bundled cocotb 2.1.0.dev0 instead of the pinned 2.1.0. Working invocation (from the repo root):
```bash
source ~/tools/oss-cad-suite/environment
source .venv/bin/activate
export PATH=$HOME/tools/oss-cad-suite/libexec:$PATH   # unwrapped iverilog/vvp first
cd test && make        # not `make -C test`: it breaks the template Makefile
```
CI pins cocotb 2.0.1 (`test/requirements.txt`, the upstream template pin; 2.1.0 breaks the gl_test `grep failure` check, see `docs/log/G0-flow.md`). Locally 2.1.0 is fine.
Check the log line `Initialized cocotb v2.1.0 from .../.venv/lib/python3.14/site-packages/cocotb`.
