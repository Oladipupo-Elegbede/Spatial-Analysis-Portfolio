# Nigeria drought dashboard

An interactive R Shiny dashboard for drought monitoring across Nigeria from 1981 to 2024. It calculates SPI-12 and SPEI-12 drought indices from CRU TS v4.09 gridded climate data, identifies drought events with the Theory of Runs, and summarises drought hotspots by state and by river catchment.

Built for GG5567 Advanced Spatial Analysis and Programming, MSc GIS and Remote Sensing, University of Aberdeen (2026).

## What the dashboard does

- Maps SPI-12 or SPEI-12 for any month between January 1981 and December 2024 on a Leaflet map
- Click any point in Nigeria to plot the full 44 year drought index record at that location, with the moderate, severe and extreme thresholds marked
- Shows a choropleth of drought hotspots across Nigeria's 37 states, switchable between persistence, number of events and mean severity at three drought thresholds

## Method

1. **Data preparation** (`00_data_prep.R`). Loads CRU TS v4.09 monthly precipitation and potential evapotranspiration (PET), crops and masks them to Nigeria, and filters to 1981 to 2024 (528 months). State and LGA boundaries come from GADM v4.1. HydroBASINS Level 6 sub-catchments are clipped to the national boundary.
2. **Drought indices** (`01_indices.R`). Calculates SPI-12 from precipitation and SPEI-12 from the climatic water balance (precipitation minus PET) for every 0.5° grid cell, using the SPEI package through `terra::app()`. Each output is checked for valid values after it is written.
3. **Drought events** (`02_events.R`). Applies the Theory of Runs at three thresholds (moderate ≤ −1.0, severe ≤ −1.5, extreme ≤ −2.0) and computes persistence, event count, mean duration and mean severity for each cell. Results are aggregated to 37 states and 146 HydroBASINS sub-catchments with area weighted zonal statistics (`exactextractr`).
4. **Dashboard** (`app.R`). Shiny and bslib interface with a Leaflet map, ggplot2 time series and a state level choropleth.

## Main findings

- Northern states, particularly Adamawa, Borno and Yobe, show the highest moderate drought persistence, spending 15 to 18 per cent of the 44 year period in drought. Southern states such as Rivers, Bayelsa and Cross River sit at 10 to 12 per cent.
- SPEI-12 shows more severe drought than SPI-12 across the north. SPEI accounts for evaporative demand, so precipitation only indices are likely to underestimate drought in the hotter Sahel zone.

## Running it

The dashboard runs straight from this repository, because the processed rasters and hotspot tables it needs are included in `Processed_Data/`.

```r
install.packages(c(
  "terra", "sf", "SPEI", "exactextractr", "geodata",
  "tidyverse", "shiny", "bslib", "leaflet", "ggplot2"
))

shiny::runApp("RScript/app.R")
```

Tested on R 4.5.2 and 4.6.0.

### Rebuilding from raw data

The raw files are too large for GitHub, so download them first:

- CRU TS v4.09 precipitation and PET (`cru_ts4.09.1901.2024.pre.dat.nc`, `cru_ts4.09.1901.2024.pet.dat.nc`) from the [CRU data repository](https://crudata.uea.ac.uk/cru/data/hrg/). Decompress them into `Raw_Data/cru/`.
- HydroBASINS Africa (`hybas_af_lev01-12_v1c.zip`) from [HydroSHEDS](https://www.hydrosheds.org/products/hydrobasins). Extract it into `Raw_Data/hydrobasins/`.

GADM boundaries download automatically. With the project root as the working directory, run the scripts in order:

```r
source("RScript/00_data_prep.R")   # about 5 to 10 minutes
source("RScript/01_indices.R")     # about 10 to 15 minutes
source("RScript/02_events.R")      # about 15 to 25 minutes
shiny::runApp("RScript/app.R")
```

## Repository structure

```
nigeria-drought-dashboard/
├── RScript/
│   ├── 00_data_prep.R      Load, crop and mask climate and boundary data
│   ├── 01_indices.R        Calculate SPI-12 and SPEI-12
│   ├── 02_events.R         Theory of Runs, hotspot metrics, zonal aggregation
│   └── app.R               Shiny dashboard
├── Processed_Data/         Outputs the dashboard reads at startup
└── Raw_Data/               Place downloaded CRU and HydroBASINS files here
```

## Known limitations

- Only the 12 month timescale is used. Shorter accumulation periods (1, 3 and 6 months) failed to converge in the SPEI package, because individual 0.5° CRU cells over Nigeria had too little variance.
- Mean event duration is calculated but left out of the dashboard, since NA handling at the masked raster edges returned NaN values.
- In terra 1.9.25 on Windows, SpatRaster objects lose their data pointer when saved as `.rds` and reloaded. The pipeline writes rasters to GeoTIFF and reads them back from disk to avoid this.
- CRU TS is a coarse 0.5° product, so results suit national and regional patterns better than local assessment.

## Data sources

| Dataset | Source | Reference |
|-|-|-|
| CRU TS v4.09 precipitation and PET | Climatic Research Unit, University of East Anglia | Harris et al. (2020) |
| Nigeria administrative boundaries | GADM v4.1 | Hijmans (2023) |
| HydroBASINS Africa Level 6 | HydroSHEDS | Lehner and Grill (2013) |

Harris, I., Osborn, T.J., Jones, P. and Lister, D. (2020) 'Version 4 of the CRU TS monthly high-resolution gridded multivariate climate dataset', *Scientific Data*, 7(1), p. 109.

Hijmans, R.J. (2023) *geodata: Download Geographic Data*. R package version 0.5-9. Available at: https://CRAN.R-project.org/package=geodata

Lehner, B. and Grill, G. (2013) 'Global river hydrography and network routing: baseline data and new approaches to study the world's large river systems', *Hydrological Processes*, 27(15), pp. 2171–2186.
