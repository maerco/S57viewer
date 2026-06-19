#!/usr/bin/env bash
# Pipeline di test: scarica una cella ENC NOAA (S-57), converte in GeoJSON
# e genera MBTiles vettoriali pronti per MapLibre.
#
# Prerequisiti (Ubuntu):
#   sudo apt-get install -y gdal-bin
#   npm install -g tippecanoe   # oppure: apt-get install -y tippecanoe (se disponibile)
#
# Uso:
#   ./s57_to_mbtiles.sh US5CA72M   # San Diego / Mission Bay (buon mix porto+secche+costa)

set -euo pipefail

CELL="${1:-US5CA72M}"
WORKDIR="./s57_work/${CELL}"
OUT_MBTILES="./output/${CELL}.mbtiles"

mkdir -p "${WORKDIR}" "$(dirname "${OUT_MBTILES}")"
cd "${WORKDIR}"

echo "==> Download cella ENC: ${CELL}"
curl -fsSL "https://www.charts.noaa.gov/ENCs/${CELL}.zip" -o "${CELL}.zip"

echo "==> Estrazione"
unzip -oq "${CELL}.zip"

# Il file .000 è il file S-57 principale (ENC base cell)
S57_FILE=$(find . -iname "*.000" | head -n1)
if [ -z "${S57_FILE}" ]; then
  echo "ERRORE: nessun file .000 trovato nello zip" >&2
  exit 1
fi
echo "==> File S-57 trovato: ${S57_FILE}"

echo "==> Layer disponibili nella cella:"
ogrinfo -ro "${S57_FILE}" | grep -E "^[0-9]+:" || true

# Layer principali per il rendering "nautico moderno":
# DEPARE  = depth area (poligoni di profondità, per il gradiente batimetrico)
# DEPCNT  = depth contour (isobate)
# SOUNDG  = soundings (scandagli puntuali)
# LNDARE  = land area
# COALNE  = coastline
# BOYLAT/BOYCAR/BOYSAW/BCNLAT ecc = boe e segnalamenti
# OBSTRN  = ostacoli
# WRECKS  = relitti
LAYERS=(DEPARE DEPCNT SOUNDG LNDARE COALNE BOYLAT BOYCAR BOYSAW BCNLAT BCNCAR LIGHTS OBSTRN WRECKS RESARE)

echo "==> Conversione layer S-57 -> GeoJSON (EPSG:4326)"
GEOJSON_FILES=()
for layer in "${LAYERS[@]}"; do
  out="${layer}.geojson"
  if ogr2ogr -f GeoJSON -t_srs EPSG:4326 \
      -where "1=1" \
      "${out}" "${S57_FILE}" "${layer}" 2>/dev/null; then
    # Scarta file vuoti (layer non presenti in questa cella)
    if [ -s "${out}" ] && grep -q '"features": \[.\+' "${out}" 2>/dev/null; then
      GEOJSON_FILES+=("${out}")
      echo "    OK: ${layer}"
    else
      rm -f "${out}"
    fi
  fi
done

if [ ${#GEOJSON_FILES[@]} -eq 0 ]; then
  echo "ERRORE: nessun layer convertito con successo" >&2
  exit 1
fi

echo "==> Generazione MBTiles con tippecanoe"
cd - > /dev/null
tippecanoe -o "${OUT_MBTILES}" \
  --force \
  -zg \
  --drop-densest-as-needed \
  --extend-zooms-if-still-dropping \
  -L depare:"${WORKDIR}/DEPARE.geojson" \
  -L depcnt:"${WORKDIR}/DEPCNT.geojson" \
  -L soundg:"${WORKDIR}/SOUNDG.geojson" \
  -L lndare:"${WORKDIR}/LNDARE.geojson" \
  -L coalne:"${WORKDIR}/COALNE.geojson" \
  2>/dev/null || echo "Nota: alcuni layer potrebbero mancare per questa cella, normale."

echo "==> Fatto: ${OUT_MBTILES}"
ls -lh "${OUT_MBTILES}"
