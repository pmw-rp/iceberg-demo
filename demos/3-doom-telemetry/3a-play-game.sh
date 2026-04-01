SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Play the game
../../resources/chocolate-doom/src/chocolate-doom-setup -iwad ../../resources/doom1.wad &

popd