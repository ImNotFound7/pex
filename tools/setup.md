# Toolchain setup (macOS arm64)

Versions: see `versions.txt`. OCaml 5.2.1 worked with hardcaml v0.17.0; no fallback needed.
cocotb 2.1.0 installs and imports under system Python 3.14.7; no Homebrew python needed.

```bash
brew install opam
opam init -y --bare --disable-sandboxing
opam switch create pex 5.2.1
eval $(opam env --switch=pex)
opam install -y dune hardcaml hardcaml_waveterm ppx_hardcaml ppx_expect ppx_jane ppx_yojson_conv yojson

# OSS CAD Suite 2026-10-25 -> ~/tools/oss-cad-suite (delete tarball after extracting)
mkdir -p ~/tools/dl && cd ~/tools/dl
curl -LO https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-10-25/oss-cad-suite-darwin-arm64-20261025.tgz
tar xzf oss-cad-suite-darwin-arm64-20261025.tgz -C ~/tools && rm -rf ~/tools/dl
source ~/tools/oss-cad-suite/environment

# from repo root
python3 -m venv .venv
.venv/bin/pip install cocotb pytest
```

Every new shell: `eval $(opam env --switch=pex); source ~/tools/oss-cad-suite/environment`.

Verify:
```bash
ocaml -version; opam list hardcaml; iverilog -V | head -1; verilator --version; yosys -V; sby --help | head -1; .venv/bin/python -c "import cocotb; print(cocotb.__version__)"
```
Notes: `iverilog -V` also prints harmless "Unable to get version" lines to stderr. `--disable-sandboxing` is used because opam's macOS sandbox is unavailable in non-interactive runs.
