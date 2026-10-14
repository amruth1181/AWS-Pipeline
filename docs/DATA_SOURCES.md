# Data sources

## 1. Vélib' Métropole — live station data (GBFS 1.0)

- Docs page: https://www.velib-metropole.fr/donnees-open-data-gbfs-du-service-velib-metropole
- Feeds (no API key, JSON, refreshed **every minute**):
  - `https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/gbfs.json`
  - `https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/station_information.json`
  - `https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/station_status.json`
  - `https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/system_information.json`
- License: Licence Ouverte / Open Licence (Etalab), **attribution required**: "Données Vélib' Métropole".
- Known errors: 404 (wrong URL), 502 (temporarily unavailable). The ingester must tolerate both.
- Volume: roughly 1,500 stations. Poll every 2 minutes and emit only changed stations.

### Field notes (fill in during P1.3 from the real fixture)

| Feed | Field | Type | Notes |
|---|---|---|---|
| station_status | station_id | int/str | join key |
| station_status | stationCode | str | human code shown on the station |
| station_status | num_bikes_available | int | |
| station_status | num_bikes_available_types | list | contains `mechanical` and `ebike` counts. Verify the exact shape. |
| station_status | num_docks_available | int | |
| station_status | is_installed / is_renting / is_returning | int (0/1) | |
| station_status | last_reported | epoch s | used for idempotency |
| station_information | name, lat, lon, capacity | | static, refresh hourly |

## 2. Paris road-traffic permanent sensors (comptages routiers permanents)

- Dataset: https://opendata.paris.fr/explore/dataset/comptages-routiers-permanents/
- Mirror / description: https://www.data.gouv.fr/datasets/comptage-routier-donnees-trafic-issues-des-capteurs-permanents-1
- Published **daily** with D-1 data, rolling 13 months. Hourly measures per road arc from magnetic loop sensors:
  **flow (débit)** = vehicles per hour, **occupancy rate (taux d'occupation)** = % of time a vehicle is over the sensor.
- Historical archive (since 2010): https://opendata.paris.fr/explore/dataset/comptages-routiers-permanents-historique/
- Field notice (PDF): https://opendata.paris.fr/api/datasets/1.0/comptages-routiers-permanents/attachments/notice_donnes_trafic_capteurs_permanents_version_20190607_pdf
- License: ODbL (Paris open data). Attribution: "Ville de Paris".
- **This is not real-time.** It feeds the daily batch and analytics path (Phase 8), not the stream.

### Field notes (fill in during P8.1)

Confirm the API endpoint (Opendatasoft Explore API v2.1, `records` or `exports`) and the exact field names
from the dataset's "API" tab and the notice above. Don't guess them in code.

## 3. Synthetic generator (ours)

`services/simulator` emits `StationChangedEvent` with `synthetic=true` for load testing.
The processor never persists synthetic events; it only counts them.

## 4. Optional enrichments

- **Open-Meteo** (no key) for hourly weather features in Phase 10: https://open-meteo.com/
- **Île-de-France Mobilités PRIM** (free account and API key) for transit disruptions or next departures, if you
  want a third live source later: https://prim.iledefrance-mobilites.fr/ . Store the key in SSM Parameter Store.
- French public holidays: the `holidays` Python package.
