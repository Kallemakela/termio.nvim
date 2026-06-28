#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORDS=3
MULTILINE=
CONFIG_MODE=debug
EDITOR_MODE=integrated
LAYOUT_MODE=single
DEBUG=
AUTO=
IO_BACKEND=
HEADLESS=
POST_SETUP=
DEMO=

usage() {
	printf '%s\n' "usage: $0 [--headless] [--words N] [--multi] [--debug] [--auto] [--demo] [--post-setup EXPR] [--config debug|own] [--editor TYPE] [--backend auto|buffer] [--layout single|v|h]" >&2
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		-w|--words)
			[ "$#" -ge 2 ] || {
				usage
				exit 1
			}
			WORDS=$2
			shift 2
			;;
		-m|--multi)
			MULTILINE=1
			shift
			;;
		-d|--debug)
			DEBUG=1
			shift
			;;
		--auto)
			AUTO=1
			shift
			;;
		--headless)
			HEADLESS=1
			shift
			;;
		--demo)
			DEMO=1
			shift
			;;
		--post-setup)
			[ "$#" -ge 2 ] || {
				usage
				exit 1
			}
			POST_SETUP=$2
			shift 2
			;;
		-c|--config)
			[ "$#" -ge 2 ] || {
				usage
				exit 1
			}
			CONFIG_MODE=$2
			shift 2
			;;
		-e|--editor)
			[ "$#" -ge 2 ] || {
				usage
				exit 1
			}
			EDITOR_MODE=$2
			shift 2
			;;
		--backend)
			[ "$#" -ge 2 ] || {
				usage
				exit 1
			}
			IO_BACKEND=$2
			shift 2
			;;
		-l|--layout)
			[ "$#" -ge 2 ] || {
				usage
				exit 1
			}
			LAYOUT_MODE=$2
			shift 2
			;;
		*)
			usage
			exit 1
			;;
	esac
	done

case "$WORDS" in
	'')
		;;
	*[!0-9]*)
		printf '%s\n' "word count must be a non-negative integer" >&2
		exit 1
		;;
esac

case "$CONFIG_MODE" in
	debug|own)
		;;
	*)
		printf '%s\n' "config must be one of: debug, own" >&2
		exit 1
		;;
esac

case "$EDITOR_MODE" in
	'')
		EDITOR_MODE=integrated
		;;
esac

case "$LAYOUT_MODE" in
	single|v|h)
		;;
	*)
		printf '%s\n' "layout must be one of: single, v, h" >&2
		exit 1
		;;
esac

case "$IO_BACKEND" in
	''|auto|buffer)
		;;
	*)
		printf '%s\n' "backend must be one of: auto, buffer" >&2
		exit 1
		;;
esac

if [ "$DEMO" = 1 ] && [ -z "$WORDS" ]; then
	WORDS=0
fi

NVIM_HEADLESS=
if [ "$HEADLESS" = 1 ]; then
	NVIM_HEADLESS=--headless
fi

if [ "$CONFIG_MODE" = debug ]; then
	if [ "$HEADLESS" = 1 ]; then
		exec env LOREM_WORDS="$WORDS" MULTILINE="$MULTILINE" TERMIO_DEBUG="$DEBUG" TERMIO_AUTO="$AUTO" TERMIO_DEMO="$DEMO" TERMIO_EDITOR="$EDITOR_MODE" TERMIO_BACKEND="$IO_BACKEND" TERMIO_LAYOUT="$LAYOUT_MODE" TERMIO_POST_SETUP="$POST_SETUP" TERMIO_REPO_ROOT="$ROOT" nvim $NVIM_HEADLESS -u NONE --cmd "lua dofile([[$ROOT/dev/headless.lua]])"
	fi
	exec env LOREM_WORDS="$WORDS" MULTILINE="$MULTILINE" TERMIO_DEBUG="$DEBUG" TERMIO_AUTO="$AUTO" TERMIO_DEMO="$DEMO" TERMIO_EDITOR="$EDITOR_MODE" TERMIO_BACKEND="$IO_BACKEND" TERMIO_LAYOUT="$LAYOUT_MODE" TERMIO_REPO_ROOT="$ROOT" nvim $NVIM_HEADLESS -u "$ROOT/dev/interactive.lua"
fi

if [ "$CONFIG_MODE" = own ]; then
	if [ "$HEADLESS" = 1 ]; then
		exec env LOREM_WORDS="$WORDS" MULTILINE="$MULTILINE" TERMIO_DEBUG="$DEBUG" TERMIO_AUTO="$AUTO" TERMIO_DEMO="$DEMO" TERMIO_EDITOR="$EDITOR_MODE" TERMIO_BACKEND="$IO_BACKEND" TERMIO_LAYOUT="$LAYOUT_MODE" TERMIO_POST_SETUP="$POST_SETUP" TERMIO_REPO_ROOT="$ROOT" nvim $NVIM_HEADLESS --cmd "lua dofile([[$ROOT/dev/headless.lua]])"
	fi
	exec env LOREM_WORDS="$WORDS" MULTILINE="$MULTILINE" TERMIO_DEBUG="$DEBUG" TERMIO_AUTO="$AUTO" TERMIO_DEMO="$DEMO" TERMIO_EDITOR="$EDITOR_MODE" TERMIO_BACKEND="$IO_BACKEND" TERMIO_LAYOUT="$LAYOUT_MODE" TERMIO_REPO_ROOT="$ROOT" nvim $NVIM_HEADLESS --cmd "lua dofile([[$ROOT/dev/interactive.lua]])"
fi

printf '%s\n' "config must be one of: debug, own" >&2
exit 1
