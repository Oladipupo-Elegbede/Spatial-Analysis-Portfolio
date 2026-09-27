# ============================================================
# 02_events.R
# Purpose: Identify drought events using Theory of Runs,
# calculate event metrics, aggregate to admin and basin units
#
# Inputs: spi_12.tif, spei_12.tif from 01_indices.R
#         boundary .rds files from 00_data_prep.R
# Outputs: hotspot .rds files in Processed_Data/
#
# Adapted from: Lecture 8 (Drought event analysis)
# ============================================================

library(terra)
library(sf)
library(exactextractr)
library(tidyverse)

# Run from the project root (nigeria-drought-dashboard/), e.g. open it as an RStudio project

cat("\n============================================================\n")
cat("02_events.R — Drought event identification and hotspot analysis\n")
cat("============================================================\n\n")

# ============================================================
# Load data — indices from .tif, boundaries from .rds
# ============================================================

cat("Loading data...\n")

# Load indices directly from .tif (no pointer issues)
spi_12  <- terra::rast("Processed_Data/spi_12.tif")
spei_12 <- terra::rast("Processed_Data/spei_12.tif")

# Load boundaries from .rds (sf objects are fine in .rds)
nigeria_l1      <- readRDS("Processed_Data/nigeria_l1.rds")
nigeria_l2      <- readRDS("Processed_Data/nigeria_l2.rds")
hydrobasins_nga <- readRDS("Processed_Data/hydrobasins_nga.rds")

# Verify indices loaded correctly
cat("  ✓ SPI_12 layers:", nlyr(spi_12), "\n")
cat("  ✓ SPEI_12 layers:", nlyr(spei_12), "\n")

spi_check <- round(terra::global(spi_12[[1]], "mean", na.rm = TRUE)$mean, 4)
cat("  ✓ SPI_12 first layer mean:", spi_check, "(should not be NaN)\n")
cat("  ✓ States:", nrow(nigeria_l1), "\n")
cat("  ✓ Basins:", nrow(hydrobasins_nga), "\n\n")

if (is.nan(spi_check)) {
  stop("ERROR: SPI_12 raster is empty. Re-run 01_indices.R first.")
}

# ============================================================
# STEP 1: Define thresholds
# Reference: Lecture 8
# ============================================================

cat("STEP 1: Defining drought thresholds...\n-------\n")

thresholds <- list(moderate = -1.0, severe = -1.5, extreme = -2.0)

cat("  Moderate: ≤", thresholds$moderate, "\n")
cat("  Severe:   ≤", thresholds$severe,   "\n")
cat("  Extreme:  ≤", thresholds$extreme,  "\n\n")

# ============================================================
# STEP 2: Theory of Runs — compute metrics per cell
# Reference: Lecture 8
# ============================================================

cat("STEP 2: Applying Theory of Runs...\n-------\n")

compute_metrics <- function(index_raster, thresh_val, label) {
  cat("  [", label, "] threshold =", thresh_val, "...\n")

  # Binary drought flag: 1 = drought, 0 = no drought
  flag <- ifel(index_raster <= thresh_val, 1, 0)

  # 1. Total drought months
  n_drought_months <- sum(flag, na.rm = TRUE)

  # 2. Number of distinct drought events (runs of 1s)
  n_events <- app(flag, fun = function(v) {
    if (all(is.na(v))) return(NA_real_)
    r <- rle(na.omit(v))
    sum(r$values == 1, na.rm = TRUE)
  })

  # 3. Mean event duration (months)
  mean_duration <- app(flag, fun = function(v) {
    if (all(is.na(v))) return(NA_real_)
    r  <- rle(na.omit(v))
    dl <- r$lengths[r$values == 1]
    if (length(dl) == 0) return(NA_real_)
    mean(dl)
  })

  # 4. Mean severity (cumulative deficit per event)
  mean_severity <- app(index_raster, fun = function(v) {
    v <- na.omit(v)
    drought_idx <- which(v <= thresh_val)
    if (length(drought_idx) == 0) return(NA_real_)
    total_deficit <- sum(v[drought_idx])
    r    <- rle(ifelse(v <= thresh_val, 1, 0))
    n_ev <- sum(r$values == 1, na.rm = TRUE)
    if (n_ev == 0) return(NA_real_)
    total_deficit / n_ev
  })

  # 5. Persistence (% of time in drought)
  persistence <- (n_drought_months / nlyr(index_raster)) * 100

  cat("    ✓ Done\n")

  list(
    n_drought_months = n_drought_months,
    n_events         = n_events,
    mean_duration    = mean_duration,
    mean_severity    = mean_severity,
    persistence      = persistence
  )
}

# Compute for SPI and SPEI at all three thresholds
hotspot_stack <- list(spi = list(), spei = list())

cat("Processing SPI-12...\n")
for (thresh_name in names(thresholds)) {
  hotspot_stack$spi[[thresh_name]] <- compute_metrics(
    spi_12, thresholds[[thresh_name]], paste("SPI_12", thresh_name))
}

cat("\nProcessing SPEI-12...\n")
for (thresh_name in names(thresholds)) {
  hotspot_stack$spei[[thresh_name]] <- compute_metrics(
    spei_12, thresholds[[thresh_name]], paste("SPEI_12", thresh_name))
}

cat("\n")

# ============================================================
# STEP 3: Aggregate to Nigeria level 1 (states)
# ============================================================

cat("STEP 3: Aggregating to states...\n-------\n")

hotspot_by_admin <- list()

for (index_type in c("spi", "spei")) {
  hotspot_by_admin[[index_type]] <- list()

  for (thresh_name in names(thresholds)) {
    cat(" ", toupper(index_type), thresh_name, "...\n")

    m <- hotspot_stack[[index_type]][[thresh_name]]

    hotspot_by_admin[[index_type]][[thresh_name]] <- data.frame(
      state_name       = nigeria_l1$NAME_1,
      state_id         = nigeria_l1$GID_1,
      n_drought_months = exact_extract(m$n_drought_months, nigeria_l1, "mean"),
      n_events         = exact_extract(m$n_events,         nigeria_l1, "mean"),
      mean_duration    = exact_extract(m$mean_duration,    nigeria_l1, "mean"),
      mean_severity    = exact_extract(m$mean_severity,    nigeria_l1, "mean"),
      persistence      = exact_extract(m$persistence,      nigeria_l1, "mean")
    )
  }
}

# Quick check: print first few rows of SPI moderate
cat("\n  Sample state aggregation (SPI moderate):\n")
print(head(hotspot_by_admin$spi$moderate[, c("state_name","persistence")], 5))
cat("\n")

# ============================================================
# STEP 4: Aggregate to HydroBASINS level 6
# ============================================================

cat("STEP 4: Aggregating to hydrological basins...\n-------\n")

hotspot_by_basin <- list()

for (index_type in c("spi", "spei")) {
  hotspot_by_basin[[index_type]] <- list()

  for (thresh_name in names(thresholds)) {
    cat(" ", toupper(index_type), thresh_name, "...\n")

    m <- hotspot_stack[[index_type]][[thresh_name]]

    hotspot_by_basin[[index_type]][[thresh_name]] <- data.frame(
      basin_id         = hydrobasins_nga$HYBAS_ID,
      n_drought_months = exact_extract(m$n_drought_months, hydrobasins_nga, "mean"),
      n_events         = exact_extract(m$n_events,         hydrobasins_nga, "mean"),
      mean_duration    = exact_extract(m$mean_duration,    hydrobasins_nga, "mean"),
      mean_severity    = exact_extract(m$mean_severity,    hydrobasins_nga, "mean"),
      persistence      = exact_extract(m$persistence,      hydrobasins_nga, "mean")
    )
  }
}

cat("\n")

# ============================================================
# STEP 5: LGA resolution demo
# ============================================================

cat("STEP 5: LGA supplementary analysis (resolution demo)...\n-------\n")

lga_metrics <- data.frame(
  lga_name   = nigeria_l2$NAME_2,
  lga_id     = nigeria_l2$GID_2,
  state_name = nigeria_l2$NAME_1,
  persistence_spi12_moderate = exact_extract(
    hotspot_stack$spi$moderate$persistence,
    nigeria_l2, "mean"
  )
)

cat("  ✓ LGA metrics extracted:", nrow(lga_metrics), "LGAs\n\n")

# ============================================================
# STEP 6: Save all outputs
# ============================================================

cat("STEP 6: Saving outputs...\n-------\n")

saveRDS(hotspot_stack,    "Processed_Data/hotspot_stack.rds")
saveRDS(hotspot_by_admin, "Processed_Data/hotspot_by_admin.rds")
saveRDS(hotspot_by_basin, "Processed_Data/hotspot_by_basin.rds")
saveRDS(lga_metrics,      "Processed_Data/lga_metrics.rds")

cat("  ✓ hotspot_stack.rds\n")
cat("  ✓ hotspot_by_admin.rds\n")
cat("  ✓ hotspot_by_basin.rds\n")
cat("  ✓ lga_metrics.rds\n\n")

# Verify hotspot_by_admin has real values
cat("  Verification — SPI moderate persistence (first 3 states):\n")
print(hotspot_by_admin$spi$moderate[1:3, c("state_name", "persistence")])
cat("\n")

gc()

cat("============================================================\n")
cat("✓ DROUGHT EVENT ANALYSIS COMPLETE\n")
cat("Next: Run app.R\n")
cat("============================================================\n\n")
