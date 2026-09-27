# ============================================================
# 01_indices.R
# Purpose: Calculate SPI-12 and SPEI-12 for Nigeria 1981-2024
# Loads from .tif files throughout to avoid terra pointer issues
#
# Inputs: pre_nigeria.tif, pet_nigeria.tif from Processed_Data/
# Outputs: spi_12.tif, spei_12.tif in Processed_Data/
#
# Adapted from: Lecture 7 (Drought indices computation)
# ============================================================

library(terra)
library(SPEI)
library(tidyverse)

# Run from the project root (nigeria-drought-dashboard/), e.g. open it as an RStudio project

cat("\n============================================================\n")
cat("01_indices.R — SPI-12 and SPEI-12 calculation for Nigeria\n")
cat("============================================================\n\n")

# ============================================================
# Load from .tif files (avoids .rds pointer issues entirely)
# ============================================================

cat("Loading climate data from .tif files...\n")

pre_nigeria <- terra::rast("Processed_Data/pre_nigeria.tif")
pet_nigeria <- terra::rast("Processed_Data/pet_nigeria.tif")

cat("  ✓ Precipitation layers:", nlyr(pre_nigeria), "\n")
cat("  ✓ PET layers:", nlyr(pet_nigeria), "\n")

# Verify data is valid
pre_check <- round(terra::global(pre_nigeria[[1]], "mean", na.rm=TRUE)$mean, 3)
cat("  ✓ Pre first layer mean:", pre_check, "(should not be NaN)\n\n")

if (is.nan(pre_check)) {
  stop("ERROR: pre_nigeria.tif is empty. Run the save step first.")
}

# ============================================================
# STEP 1: Monthly standardised precipitation anomalies
# Reference: Lecture 7
# ============================================================

cat("STEP 1: Computing monthly standardised anomalies...\n-------\n")

# Rebuild date vector from layer names
layer_names <- names(pre_nigeria)
# Names are like "pre_961", so use index position to rebuild dates
# Start from 1981-01-16 with monthly steps
start_date  <- as.Date("1981-01-16")
all_dates   <- seq(start_date, by = "month", length.out = nlyr(pre_nigeria))
month_index <- as.integer(format(all_dates, "%m"))

clim_mean <- tapp(pre_nigeria, month_index, mean, na.rm = TRUE)
clim_sd   <- tapp(pre_nigeria, month_index, sd,   na.rm = TRUE)

anom_layers <- vector("list", nlyr(pre_nigeria))
for (i in seq_len(nlyr(pre_nigeria))) {
  m <- month_index[i]
  anom_layers[[i]] <- (pre_nigeria[[i]] - clim_mean[[m]]) / clim_sd[[m]]
  if (i %% 100 == 0) cat("  ", i, "/", nlyr(pre_nigeria), "\n", sep = "")
}

pre_anom <- rast(anom_layers)
time(pre_anom) <- all_dates

anom_mean <- round(mean(pre_anom[], na.rm = TRUE), 4)
anom_sd   <- round(sd(pre_anom[],   na.rm = TRUE), 4)

cat("  ✓ Mean (expect ≈ 0):", anom_mean, "\n")
cat("  ✓ SD   (expect ≈ 1):", anom_sd,   "\n\n")

rm(pre_anom, anom_layers, clim_mean, clim_sd)
gc()

# ============================================================
# STEP 2: Water balance
# Reference: Lecture 7
# ============================================================

cat("STEP 2: Computing water balance (precipitation - PET)...\n-------\n")

water_balance <- pre_nigeria - pet_nigeria

wb_mean <- round(terra::global(water_balance[[1]], "mean", na.rm=TRUE)$mean, 2)
cat("  ✓ Layers:", nlyr(water_balance), "\n")
cat("  ✓ First layer mean:", wb_mean, "\n\n")

# ============================================================
# STEP 3: SPI-12
# Reference: Lecture 7
# ============================================================

cat("STEP 3a: Computing SPI-12...\n-------\n")

spi_12 <- app(pre_nigeria, fun = function(v) {
  if (all(is.na(v))) return(rep(NA_real_, length(v)))
  as.numeric(SPEI::spi(v, scale = 12, na.rm = TRUE,
                        verbose = FALSE)$fitted)
})

# Assign informative names
names(spi_12) <- paste0("spi_12_", format(all_dates, "%Y_%m"))

spi_mean <- round(mean(spi_12[], na.rm = TRUE), 4)
spi_sd   <- round(sd(spi_12[],   na.rm = TRUE), 4)

cat("  ✓ Mean:", spi_mean, "(expect ≈ 0)\n")
cat("  ✓ SD:  ", spi_sd,   "(expect ≈ 1)\n\n")

# Save immediately
cat("  Saving SPI-12...\n")
terra::writeRaster(spi_12, "Processed_Data/spi_12.tif", overwrite = TRUE)

# Verify saved file
verify <- terra::rast("Processed_Data/spi_12.tif")
v_mean <- round(terra::global(verify[[1]], "mean", na.rm=TRUE)$mean, 4)
cat("  ✓ Verification mean:", v_mean, "(should not be NaN)\n\n")
rm(verify, spi_12)
gc()

# ============================================================
# STEP 4: SPEI-12
# Reference: Lecture 7
# ============================================================

cat("STEP 3b: Computing SPEI-12...\n-------\n")

spei_12 <- app(water_balance, fun = function(v) {
  if (all(is.na(v))) return(rep(NA_real_, length(v)))
  as.numeric(SPEI::spei(v, scale = 12, na.rm = TRUE,
                         verbose = FALSE)$fitted)
})

names(spei_12) <- paste0("spei_12_", format(all_dates, "%Y_%m"))

spei_mean <- round(mean(spei_12[], na.rm = TRUE), 4)
spei_sd   <- round(sd(spei_12[],   na.rm = TRUE), 4)

cat("  ✓ Mean:", spei_mean, "(expect ≈ 0)\n")
cat("  ✓ SD:  ", spei_sd,   "(expect ≈ 1)\n\n")

# Save immediately
cat("  Saving SPEI-12...\n")
terra::writeRaster(spei_12, "Processed_Data/spei_12.tif", overwrite = TRUE)

# Verify saved file
verify2 <- terra::rast("Processed_Data/spei_12.tif")
v_mean2 <- round(terra::global(verify2[[1]], "mean", na.rm=TRUE)$mean, 4)
cat("  ✓ Verification mean:", v_mean2, "(should not be NaN)\n\n")
rm(verify2, spei_12, water_balance)
gc()

cat("============================================================\n")
cat("✓ DROUGHT INDEX CALCULATION COMPLETE\n")
cat("  SPI_12:  mean =", spi_mean,  "| sd =", spi_sd,  "\n")
cat("  SPEI_12: mean =", spei_mean, "| sd =", spei_sd, "\n\n")
cat("Outputs saved to Processed_Data/:\n")
cat("  - spi_12.tif  (verification mean:", v_mean, ")\n")
cat("  - spei_12.tif (verification mean:", v_mean2, ")\n\n")
cat("Next: Run 02_events.R\n")
cat("============================================================\n\n")
