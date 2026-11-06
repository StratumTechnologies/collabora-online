#!/usr/bin/env bash
# Builds and installs the browser frontend the way `make -C browser` and
# `make install` do for the stock CODE image, without the engine build tree
# that ./configure insists on: automake still writes browser/Makefile.in from
# browser/Makefile.am, and this script stands in for config.status, filling
# configure's substitutions with the values of a release server build.
# Output: $DESTDIR/usr/share/coolwsd/browser/{dist,admin-templates}.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
DESTDIR=${DESTDIR:-$root/stratum/out}
TRANSLATIONS_TAG=cp-26.04.5-1

# The engine's UI translations, which become dist/l10n/uno/*.json; the repo carries the same tags as this one.
if [ ! -d engine/translations ]; then
    git clone --quiet --depth 1 --branch "$TRANSLATIONS_TAG" --filter=blob:none --no-checkout \
        https://gerrit.collaboraoffice.com/translations engine/translations
    git -C engine/translations sparse-checkout set --no-cone '/source/*/officecfg/registry/data/org/openoffice/Office/UI.po'
    git -C engine/translations checkout --quiet
fi

libtoolize --quiet
aclocal
automake --add-missing browser/Makefile

# Created after Makefile.in so make never tries to rerun configure to remake browser/Makefile.
touch configure config.status
cp browser/npm-shrinkwrap.json.in browser/npm-shrinkwrap.json

python3 - "$root" <<'EOF'
import re, sys

root = sys.argv[1]
values = {
    "SHELL": "/bin/bash",
    "srcdir": ".", "builddir": ".", "top_srcdir": "..", "top_builddir": "..",
    "abs_srcdir": f"{root}/browser", "abs_builddir": f"{root}/browser",
    "abs_top_srcdir": root, "abs_top_builddir": root,
    "prefix": "/usr", "datarootdir": "${prefix}/share", "datadir": "${datarootdir}",
    "PACKAGE": "coolwsd",
    "AM_V": "$(V)", "AM_DEFAULT_V": "$(AM_DEFAULT_VERBOSITY)", "AM_DEFAULT_VERBOSITY": "0",
    "NODE": "node", "NPM": "npm", "PYTHON": "python3",
    "ENABLE_DEBUG": "false",
    "ENABLE_BUNDLE": "true",
    "ENABLE_EXPERIMENTAL": "false",
    "APP_NAME": "Collabora Online Development Edition",
    "VENDOR": "Collabora Productivity Limited",
    "INFO_URL": "https://www.collaboraoffice.org/",
}

# CODE is configured --with-welcome-url; every other conditional (apps, debug, wasm, branding) is off.
true_conditionals = {"ENABLE_WELCOME_MESSAGE"}


def substitute(match):
    name = match.group(1)
    if name.endswith(("_TRUE", "_FALSE")):
        condition, _, branch = name.rpartition("_")
        return "" if (condition in true_conditionals) == (branch == "TRUE") else "#"
    return values.get(name, "")


makefile_in = open("browser/Makefile.in").read()
open("browser/Makefile", "w").write(re.sub(r"@(\w+)@", substitute, makefile_in))
EOF

make -C browser node_modules
make -C browser -j"$(nproc)" build-cool
make -C browser install-data-hook DESTDIR="$DESTDIR"
