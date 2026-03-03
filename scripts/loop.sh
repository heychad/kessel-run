#!/usr/bin/env bash
# The Hyperdrive — core Kessel Run loop.
# Fresh context every parsec. Stream everything. Never capture into variables.
#
# Usage:
#   ./scripts/kessel-run/loop.sh              # run KESSEL_MAX_PARSECS (default 12)
#   ./scripts/kessel-run/loop.sh 5            # run 5 parsecs
#   ./scripts/kessel-run/loop.sh 0            # unlimited parsecs
#   ./scripts/kessel-run/loop.sh watch        # single TUI iteration (no -p flag)
set -euo pipefail

KESSEL_MODEL="${KESSEL_MODEL:-claude-opus-4-6}"
KESSEL_DIR="${KESSEL_DIR:-scripts/kessel-run}"

# ── Parsec banners — one per iteration ────────────────────────────
# Art from ascii-art.de Star Wars collection by Lennert Stock et al.
parsec_banner() {
    local n=$(( ($1 - 1) % 12 ))
    echo ""
    case $n in
    0)
# ── Millennium Falcon ──
cat << 'ART'
                 _     _
                /_|   |_\
               //||   ||\\
              // ||   || \\
             //  ||___||  \\
            /     |   |     \    _
           /    __|   |__    \  /_\
          / .--~  |   |  ~--. \|   |
         /.~ __\  |   |  /   ~.|   |
        .~  `=='\ |   | /   _.-'.  |
       /  /      \|   |/ .-~    _.-'
      |           +---+  \  _.-~  |
      `=----.____/  #  \____.----='       PARSEC #XX
       [::::::::|  (_)  |::::::::]        ═══════════
      .=----~~~~~\     /~~~~~----=.
      |          /`---'\          |        "She may not look like much, but
       \  \     /       \     /  /         she's got it where it counts."
        `.     /         \     .'
          `.  /._________.\  .'
            `--._________.--'
ART
    ;;
    1)
# ── TIE Fighter ──
cat << 'ART'
      _______              _______
     /\:::::/\            /\:::::/\
    /::\:::/::\          /==\:::/::\
   /::::\_/::::\   .--. /====\_/::::\
  /_____/ \_____\-' .-.`-----' \_____\
  \:::::\_/:::::/-. `-'.-----._/:::::/
   \::::/:\::::/   `--' \::::/:\::::/
    \::/:::\::/          \::/:::\::/
     \/:::::\/            \/:::::\/
      """""""              """""""

    PARSEC #XX  //  "I have you now."
ART
    ;;
    2)
# ── X-wing (attack position) ──
cat << 'ART'
          .                            .                      .
  .                  .             -)------+====+       .
                           -)----====    ,'   ,'   .                 .
              .                  `.  `.,;___,'                .
                                   `, |____l_\
                    _,.....------c==]""______ |,,,,,,.....____ _
    .      .       "-:______________  |____l_|]'''''''''''       .     .
                                  ,'"",'.   `.
         .                 -)-----====   `.   `.
                     .            -)-------+====+       .            .
             .                               .

    PARSEC #XX  //  "Almost there... almost there..."
ART
    ;;
    3)
# ── Imperial Star Destroyer ──
cat << 'ART'
           .            .                     .
                  _        .                          .            (
                 (_)        .       .                                     .
  .        ____.--^.
   .      /:  /    |                               +           .         .
         /:  `--=--'   .                                                .
        /: __[\==`-.___          *           .
       /__|\ _~~~~~~   ~~--..__            .             .
       \   \|::::|-----.....___|~--.                                 .
        \ _\_~~~~~-----:|:::______//---...___
    .   [\  \  __  --     \       ~  \_      ~~~===------==-...____
        [============================================================-
        /         __/__   --  /__    --       /____....----''''~~~~      .
  *    /  /   ==           ____....=---='''~~~~ .
      /____....--=-''':~~~~                      .                .
      .       ~--~
                     .        PARSEC #XX  //  "Intensify forward firepower!"
ART
    ;;
    4)
# ── Death Star + Falcon ──
cat << 'ART'
            .          .
  .          .                  .          .              .
        +.           _____  .        .        + .                    .
    .        .   ,-~"     "~-.                                +
               ,^ ___         ^. +                  .    .       .
              / .^   ^.         \         .      _ .
             Y  l  o  !          Y  .         __CL\H--.
     .       l_ `.___.'        _,[           L__/_\H' \\--_-          +
             |^~"-----------""~ ^|       +    __L_(=): ]-_ _-- -
   +       . !                   !     .     T__\ /H. //---- -       .
          .   \                 /               ~^-H--'
               ^.             .^            .      "       +.
                 "-.._____.,-" .                    .

    PARSEC #XX  //  "That's no moon."
ART
    ;;
    5)
# ── AT-AT Walker ──
cat << 'ART'
                 ________
            _,.-Y  |  |  Y-._
        .-~"   ||  |  |  |   "-.
        I" ""=="|" !""! "|"[]""|     _____
        L__  [] |..------|:   _[----I" .-{"-.
       I___|  ..| l______|l_ [__L]_[I_/r(=}=-P
      [L______L_[________]______j~  '-=c_]/=-^
       \_I_j.--.\==I|I==_/.--L_]
         [_((==)[`-----"](==)j
            I--I"~~"""~~"I--I
            |[]|         |[]|
            l__j         l__j
            |!!|         |!!|
            |..|         |..|
            ([])         ([])
            ]--[         ]--[
            [_L]         [_L]
           /|..|\       /|..|\
          `=}--{='     `=}--{='
         .-^--r-^-.   .-^--r-^-.
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PARSEC #XX  //  "Imperial walkers on the north ridge!"
ART
    ;;
    6)
# ── R2-D2 ──
cat << 'ART'
         _____
       .'/L|__`.
      / =[_]O|` \
      |"+_____":|
    __:='|____`-:__
   ||[] ||====| []||
   ||[] | |=| | []||
   |:||_|=|U| |_||:|
   |:|||]_=_ =[_||:|
   | |||] [_][]C|| |
   | ||-'"""""`-|| |
   /|\\_\_|_|_/_//|\
  |___|   /|\   |___|
  `---'  |___|  `---'
         `---'

    PARSEC #XX  //  "Beep boop bweee!"
ART
    ;;
    7)
# ── X-wing (front view) ──
cat << 'ART'
     ________
   =[________]========-------[]<--
     |  ___ |
     |==|  ||
     |==| _| |
     |==||   |
     |  ||   |
     |  ||    |
     |  ~~    |
     |________|
   __L________\_
  <_|_L___/   | |,
     |__\_____|_|___
    /L___________   `---._________
   | | .----. _  |---v--.______ _ `-------------.--.__
  [| | |    |(_) |]__[_____]____________________]__ __]
   | |___________|---^--'_________.-------------`--'
    \L______________.---'
   __|__/_    | |
  <_|_L___\___|_|'
     L________/

    PARSEC #XX  //  "Lock S-foils in attack position."
ART
    ;;
    8)
# ── Darth Vader ──
cat << 'ART'
           _.-'~~~~~~`-._
          /      ||      \
         /       ||       \
        |        ||        |
        | _______||_______ |
        |/ ----- \/ ----- \|
       /  (     )  (     )  \
      / \  ----- () -----  / \
     /   \      /||\      /   \
    /     \    /||||\    /     \
   /       \  /||||||\  /       \
  /_        \o========o/        _\
    `--...__|`-._  _.-'|__...--'
            |    `'    |

    PARSEC #XX  //  "I find your lack of faith disturbing."
ART
    ;;
    9)
# ── Yoda ──
cat << 'ART'
                   ____
                _.' :  `._
            .-'.'  :   .'`-.
   __      / : ___\ ;  /___  ; \      __
 ,'_ ""--.:_;" .-.";: :".-.":_; .--"" _`,
 :' `.t""--.. '<@.`;_  ',@>` ..--""j.' `;
      `:-.._J '-.-'L__ `-- ' L_..-;'
        "-.__ ;  .-"  "-.  : __.-"
            L ' /.------\ ' J
             "-.   "--"   .-"
            __.l"-:_JL_;-";.__
         .-j/'.;  ;""""  / .'\'-.
       .' /;`. "-.:     .-" .';  `.
    .-"  / ;  "-. "-..-" .-"  :    "-.
 .+"-.  : :      "-.__.-"      ;-._   \
 ; \  `.; ;                    : : "+. ;
 :  ;   ; ;                    : ;  : \:

    PARSEC #XX  //  "Do. Or do not. There is no try."
ART
    ;;
    10)
# ── Lambda Shuttle ──
cat << 'ART'
                 ___
                /  |
               /  =|
              /   =`.
             /      |
            <_______|
        __,.----'__`+
       '------:_____]
               _|_
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~

           o
          /\           .
         |  `.
         `.   \                    .
    .      |    `.
           `.     |          .
            |     |_.--.
         .  `.   /<= .-'              .
    .        |_./|_.'/))    .
             /()_.-'/ /`-.
            / / _.-'\/_   `-.__
           (./())      ~~--..__~`-o
      .     | /   .            `-'
            //       .   .             .

    PARSEC #XX  //  "Shuttle Tydirium, what is your cargo and destination?"
ART
    ;;
    11)
# ── Wanted poster ──
cat << 'ART'
  ___________________________________________________________
 |                                                           |
 |                    W  A  N  T  E  D                       |
 |                                                           |
 |     For crimes against the PRD:                           |
 |       - Leaving items with passes: false                  |
 |       - Failure to run backpressure                       |
 |       - Unauthorized placeholder implementations          |
 |                                                           |
 |     REWARD: One working feature, fully tested             |
 |                                                           |
 |     BOUNTY HUNTERS:  Experienced Opus models only         |
 |___________________________________________________________|

    PARSEC #XX  //  "Bounty hunters. We don't need their scum."
ART
    ;;
    esac
}

# ── Star Wars banner ──────────────────────────────────────────────
echo ""
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║         K E S S E L   R U N                       ║"
echo "  ║   The fastest hunk of junk in the galaxy          ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────
PREFLIGHT_OK=true

for f in "${KESSEL_DIR}/PROMPT.md" PRD.json "${KESSEL_DIR}/backpressure.sh" PROGRESS.md; do
    if [ ! -f "$f" ]; then
        echo "  [FAIL] Missing: $f"
        PREFLIGHT_OK=false
    fi
done

if [ "$PREFLIGHT_OK" = false ]; then
    echo ""
    echo "  Pre-flight check failed. Run init.sh first."
    echo "  \"She may not look like much, but she's got it where it counts.\""
    exit 1
fi

echo "  Pre-flight check ........... ALL GREEN"
echo "  Navigation computer ........ ${KESSEL_DIR}/PROMPT.md"
echo "  Star chart ................. PRD.json"
echo "  Deflector shields .......... ${KESSEL_DIR}/backpressure.sh"
echo "  Ship's log ................. PROGRESS.md"
echo "  Hyperdrive ................. ${KESSEL_MODEL}"
echo ""

# ── Watch mode (single TUI iteration) ─────────────────────────────
if [ "${1:-}" = "watch" ]; then
    echo "  ── WATCH MODE ── Single parsec in TUI ──"
    echo ""
    cat "${KESSEL_DIR}/PROMPT.md" | claude \
        --model "$KESSEL_MODEL" \
        --dangerously-skip-permissions \
        --verbose
    echo ""
    echo "  ── WATCH MODE COMPLETE ──"
    exit 0
fi

# ── Parse parsec count ─────────────────────────────────────────────
MAX_PARSECS="${1:-${KESSEL_MAX_PARSECS:-12}}"
PARSEC=0

echo "  Plotting course: ${MAX_PARSECS} parsecs (0 = unlimited)"
echo ""

# ── Completion check ───────────────────────────────────────────────
check_all_complete() {
    python3 -c "
import json, sys
with open('PRD.json') as f:
    data = json.load(f)
items = data.get('items', [])
if not items:
    sys.exit(1)
sys.exit(0 if all(i.get('passes') for i in items) else 1)
" 2>/dev/null
}

# ── The Kessel Run ─────────────────────────────────────────────────
while true; do
    PARSEC=$((PARSEC + 1))

    if [ "$MAX_PARSECS" -gt 0 ] && [ "$PARSEC" -gt "$MAX_PARSECS" ]; then
        echo ""
        echo "  ════════════════════════════════════════════"
        echo "  MAX PARSECS ($MAX_PARSECS) REACHED"
        echo "  \"Great shot kid, that was one in a million!\""
        echo "  ════════════════════════════════════════════"
        break
    fi

    # Show parsec banner (cycles through 12 designs)
    parsec_banner "$PARSEC" | sed "s/#XX/#${PARSEC}/g"
    echo "  $(date '+%H:%M:%S')"
    echo ""

    # Stream output directly — never capture into variables
    cat "${KESSEL_DIR}/PROMPT.md" | claude -p \
        --model "$KESSEL_MODEL" \
        --dangerously-skip-permissions \
        --output-format=text \
        --verbose 2>&1 || true

    echo ""
    echo "  ── END PARSEC #${PARSEC} ──"

    # Check if all PRD items pass
    if check_all_complete; then
        echo ""
        echo "  ╔═══════════════════════════════════════════════════╗"
        echo "  ║         H Y P E R S P A C E   C O M P L E T E    ║"
        echo "  ║                                                   ║"
        echo "  ║   All PRD items passing after ${PARSEC} parsecs.        ║"
        echo "  ║   \"It's not my fault!\" — It's nobody's fault.     ║"
        echo "  ║   The Kessel Run is done.                         ║"
        echo "  ╚═══════════════════════════════════════════════════╝"

        # macOS notification
        if command -v osascript &>/dev/null; then
            osascript -e "display notification \"All PRD items passing after ${PARSEC} parsecs.\" with title \"Kessel Run Complete\" sound name \"Glass\""
        fi
        break
    fi
done
