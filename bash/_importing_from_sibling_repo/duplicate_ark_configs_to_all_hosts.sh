# Path leading to the Game.ini Allowed Steam etc. /mnt/bulk_store/Server/_docker-stack/ark-se/TMC/theisland/config/
source_dir=/mnt/bulk_store/Server/_docker-stack/ark-se/TMC/theisland/config
destination_base_dir=/mnt/bulk_store/Server/_docker-stack/ark-se/TMC
maps_installed=( "aberration" "extinction" "lostisland" "scorchedearth" "theisland" "crystalisles" "fjordur" "ragnarok" "thecenter" "valguero" )
for map in "${maps_installed[@]}"; do
    sudo cp $source_dir/AllowedCheaterSteamIDs.txt $destination_base_dir/$map/
    sudo cp $source_dir/GameUserSettings.ini $destination_base_dir/$map/
    sudo cp $source_dir/Game.ini $destination_base_dir/$map/
    done