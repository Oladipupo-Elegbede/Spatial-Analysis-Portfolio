# ============================================================
# 00_data_prep.R
# Purpose: Load raw CRU and boundary data, verify integrity,
# crop/mask to Nigeria, save interim outputs
#
# Inputs: Raw CRU .nc files, HydroBASINS shapefile
# Outputs: .rds files in Processed_Data/
#
# Adapted from: Lecture 7 (Drought indices computation)
# ============================================================

library(terra)
library(sf)
library(tidyverse)

# Run from the project root (nigeria-drought-dashboard/), e.g. open it as an RStudio project

cat("\n============================================================\n")
cat("00_data_prep.R — Data preparation for Nigeria drought analysis\n")
cat("============================================================\n\n")

# Create output folder if it doesn't exist
dir.create("Processed_Data", showWarnings = FALSE)

# ============================================================
# STEP 1: Load CRU data
# ============================================================

cat("STEP 1: Loading CRU climate data...\n-------\n")

pre_global <- rast("Raw_Data/cru/cru_ts4.09.1901.2024.pre.dat.nc", subds = "pre")
pet_global <- rast("Raw_Data/cru/cru_ts4.09.1901.2024.pet.dat.nc")

cat("  ✓ Precipitation layers:", nlyr(pre_global), "\n")
cat("  ✓ PET layers:", nlyr(pet_global), "\n")
cat("  ✓ Time range:", as.character(time(pre_global)[1]),
    "to", as.character(time(pre_global)[nlyr(pre_global)]), "\n\n")

# ============================================================
# STEP 2: Load Nigeria admin boundaries
# ============================================================

cat("STEP 2: Loading Nigeria administrative boundaries...\n-------\n")

nigeria_l1 <- geodata::gadm(country = "NGA", level = 1,
                             path = "Raw_Data/gadm") |> sf::st_as_sf()
nigeria_l2 <- geodata::gadm(country = "NGA", level = 2,
                             path = "Raw_Data/gadm") |> sf::st_as_sf()

cat("  ✓ States:", nrow(nigeria_l1), "\n")
cat("  ✓ LGAs:", nrow(nigeria_l2), "\n\n")

# ============================================================
# STEP 3: Load HydroBASINS and clip to Nigeria
# ============================================================

cat("STEP 3: Loading HydroBASINS level 6...\n-------\n")

hydrobasins_raw <- st_read("Raw_Data/hydrobasins/hybas_af_lev06_v1c.shp",
                            quiet = TRUE)

cat("  ✓ Total Africa sub-basins:", nrow(hydrobasins_raw), "\n")

# Disable S2 to avoid geometry validation errors
sf::sf_use_s2(FALSE)
hydrobasins_nga <- st_intersection(hydrobasins_raw,
                                    st_union(st_geometry(nigeria_l1)))
sf::sf_use_s2(TRUE)

cat("  ✓ Nigeria sub-basins:", nrow(hydrobasins_nga), "\n\n")

# ============================================================
# STEP 4: Reproject all boundaries to match CRU CRS
# ============================================================

cat("STEP 4: Reprojecting boundaries to WGS84...\n-------\n")

nigeria_l1      <- st_transform(nigeria_l1,      crs(pre_global))
nigeria_l2      <- st_transform(nigeria_l2,      crs(pre_global))
hydrobasins_nga <- st_transform(hydrobasins_nga, crs(pre_global))

cat("  ✓ All boundaries in WGS84\n\n")

# ============================================================
# STEP 5: Crop and mask to Nigeria
# ============================================================

cat("STEP 5: Cropping and masking to Nigeria...\n-------\n")

pre_nigeria <- crop(pre_global, nigeria_l1)
pre_nigeria <- mask(pre_nigeria, nigeria_l1)

pet_nigeria <- crop(pet_global, nigeria_l1)
pet_nigeria <- mask(pet_nigeria, nigeria_l1)

cat("  ✓ Cropped dimensions:", dim(pre_nigeria)[1], "x",
    dim(pre_nigeria)[2], "\n\n")

# ============================================================
# STEP 6: Filter to 1981-2024
# ============================================================

cat("STEP 6: Filtering to 1981-2024...\n-------\n")

all_dates   <- as.Date(time(pre_nigeria))
sel         <- all_dates >= as.Date("1981-01-01")

pre_nigeria <- pre_nigeria[[which(sel)]]
pet_nigeria <- pet_nigeria[[which(sel)]]
time(pre_nigeria) <- all_dates[sel]
time(pet_nigeria) <- all_dates[sel]

cat("  ✓ Months retained:", nlyr(pre_nigeria), "\n")
cat("  ✓ Period:", as.character(time(pre_nigeria)[1]),
    "to", as.character(time(pre_nigeria)[nlyr(pre_nigeria)]), "\n\n")

# ============================================================
# STEP 7: Data completeness check
# ============================================================

cat("STEP 7: Checking data completeness...\n-------\n")

n_total  <- ncell(pre_nigeria) * nlyr(pre_nigeria)
n_valid  <- sum(!is.na(pre_nigeria[]))
pct      <- round(100 * n_valid / n_total, 1)

cat("  Data completeness:", pct, "%\n")
if (pct > 70) {
  cat("  ✓ PASS: Sufficient coverage for analysis\n\n")
} else {
  cat("  ⚠ WARNING: Low coverage — check masking\n\n")
}

# ============================================================
# STEP 8: Save outputs
# ============================================================

cat("STEP 8: Saving processed datasets...\n-------\n")

saveRDS(pre_nigeria,     "Processed_Data/pre_nigeria_1981_2024.rds")
saveRDS(pet_nigeria,     "Processed_Data/pet_nigeria_1981_2024.rds")
saveRDS(nigeria_l1,      "Processed_Data/nigeria_l1.rds")
saveRDS(nigeria_l2,      "Processed_Data/nigeria_l2.rds")
saveRDS(hydrobasins_nga, "Processed_Data/hydrobasins_nga.rds")

# Save climate rasters as GeoTIFF as well. SpatRaster objects lose their data
# pointer when saved as .rds, so 01_indices.R reads these .tif files instead
writeRaster(pre_nigeria, "Processed_Data/pre_nigeria.tif", overwrite = TRUE)
writeRaster(pet_nigeria, "Processed_Data/pet_nigeria.tif", overwrite = TRUE)

cat("  ✓ pre_nigeria_1981_2024.rds\n")
cat("  ✓ pet_nigeria_1981_2024.rds\n")
cat("  ✓ nigeria_l1.rds\n")
cat("  ✓ nigeria_l2.rds\n")
cat("  ✓ hydrobasins_nga.rds\n")
cat("  ✓ pre_nigeria.tif\n")
cat("  ✓ pet_nigeria.tif\n\n")

# Clean up
rm(pre_global, pet_global, hydrobasins_raw, all_dates, sel)
gc()

cat("============================================================\n")
cat("✓ DATA PREPARATION COMPLETE\n")
cat("Next: Run 01_indices.R\n")
cat("============================================================\n\n")
