# ============================================================
# app.R
# Nigeria Drought Dashboard
# Loads from Processed_Data/ — structure confirmed from diagnostics
#
# Data confirmed:
#   spi_12.tif / spei_12.tif: 528 layers named lyr.1 to lyr.528
#   hotspot_by_admin: nested list spi/spei > moderate/severe/extreme
#   Valid metrics: persistence, n_events, mean_severity
#   nigeria_l1.rds: 37 states, field NAME_1
#
# Adapted from: Lecture 9 (Dashboard development)
# ============================================================

library(shiny)
library(bslib)
library(leaflet)
library(terra)
library(sf)
library(ggplot2)
library(tidyverse)
library(exactextractr)

# shiny::runApp() sets the working directory to RScript/, so step up to the
# project root if Processed_Data/ is not found here
if (!dir.exists("Processed_Data")) setwd("..")

cat("Loading data...\n")

# Load indices from .tif
spi_12  <- terra::rast("Processed_Data/spi_12.tif")
spei_12 <- terra::rast("Processed_Data/spei_12.tif")

# Build date vector from position (layers named lyr.1 to lyr.528)
# Period: 1981-01 to 2024-12 = 528 months
start_date  <- as.Date("1981-01-16")
all_dates   <- seq(start_date, by = "month", length.out = nlyr(spi_12))
date_labels <- format(all_dates, "%Y-%m")

# Load boundaries and hotspot data
nigeria_l1       <- readRDS("Processed_Data/nigeria_l1.rds") |>
                    sf::st_transform(4326)
hotspot_by_admin <- readRDS("Processed_Data/hotspot_by_admin.rds")

cat("  SPI-12 layers:", nlyr(spi_12), "\n")
cat("  Date range:", date_labels[1], "to", tail(date_labels, 1), "\n")
cat("  Admin regions:", nrow(nigeria_l1), "\n")
cat("Ready.\n")

# ============================================================
# UI
# ============================================================

ui <- page_sidebar(
  title = "Nigeria Drought Dashboard",
  theme = bs_theme(bootswatch = "minty"),

  sidebar = sidebar(
    width = 280,

    selectInput("index_type", "Index",
                choices  = c("SPI", "SPEI"),
                selected = "SPI"),

    radioButtons("scale", "Scale (months)",
                 choices  = "12",
                 selected = "12"),

    selectInput("date_choice", "Month",
                choices  = date_labels,
                selected = tail(date_labels, 1)),

    selectInput("threshold", "Drought threshold",
                choices  = c("Moderate (≤ −1.0)" = "moderate",
                             "Severe (≤ −1.5)"   = "severe",
                             "Extreme (≤ −2.0)"  = "extreme"),
                selected = "moderate"),

    selectInput("hotspot_metric", "Hotspot metric",
                choices  = c("Persistence (%)"  = "persistence",
                             "No. of events"    = "n_events",
                             "Mean severity"    = "mean_severity"),
                selected = "persistence"),

    hr(),
    p("Click the map to view the drought time series at that location.",
      style = "font-size:0.85em; color:#666;")
  ),

  layout_columns(
    col_widths = c(7, 5),

    card(
      card_header("Drought Map"),
      leafletOutput("drought_map", height = 460)
    ),

    card(
      card_header("Drought Hotspot by State"),
      plotOutput("hotspot_plot", height = 460)
    ),

    card(
      card_header("Time Series — click map to select location"),
      plotOutput("ts_plot", height = 280)
    ),

    card(
      card_header("About"),
      p("This dashboard displays SPI-12 and SPEI-12 drought indices
        for Nigeria, calculated from CRU TS v4.09 gridded climate
        data (1981–2024) at 0.5° spatial resolution."),
      p("Drought events are identified using the Theory of Runs with
        three severity thresholds: moderate (≤ −1.0), severe (≤ −1.5),
        and extreme (≤ −2.0). The 12-month timescale captures cumulative
        annual drought, the most policy-relevant scale for agricultural
        and water resource assessment in Nigeria."),
      p("SPEI-12 incorporates evaporative demand (PET) alongside
        precipitation, making it more sensitive to temperature-driven
        drought stress in Nigeria's Sahel zone compared to SPI-12."),
      p(strong("Data: "), "CRU TS v4.09 (Harris et al., 2020);
        GADM v4.1; HydroBASINS Africa Level 6."),
      p(strong("Author: "),
        "Oladipupo Elegbede | MSc GIS and Remote Sensing, University of Aberdeen")
    )
  )
)

# ============================================================
# SERVER
# ============================================================

server <- function(input, output, session) {

  # ----------------------------------------------------------
  # Select correct index raster
  # ----------------------------------------------------------
  selected_stack <- reactive({
    if (input$index_type == "SPI") spi_12 else spei_12
  })

  # ----------------------------------------------------------
  # Select single layer by date label
  # ----------------------------------------------------------
  selected_layer <- reactive({
    idx <- which(date_labels == input$date_choice)
    req(length(idx) >= 1)
    selected_stack()[[idx[1]]]
  })

  # ----------------------------------------------------------
  # Base leaflet map
  # ----------------------------------------------------------
  output$drought_map <- renderLeaflet({
    leaflet() |>
      addTiles() |>
      addPolygons(
        data    = nigeria_l1,
        fill    = FALSE,
        color   = "black",
        weight  = 1.2,
        opacity = 0.9,
        label   = ~NAME_1
      ) |>
      setView(lng = 8.68, lat = 9.08, zoom = 5)
  })

  # ----------------------------------------------------------
  # Update raster overlay reactively
  # ----------------------------------------------------------
  observe({
    lyr     <- selected_layer()
    lyr_wgs <- terra::project(lyr, "EPSG:4326", method = "bilinear")

    pal <- colorNumeric(
      palette  = c("#B2182B", "#F4A582", "white", "#92C5DE", "#2166AC"),
      domain   = c(-3, 3),
      na.color = "transparent"
    )

    leafletProxy("drought_map") |>
      clearImages() |>
      clearControls() |>
      addRasterImage(lyr_wgs, colors = pal, opacity = 0.75,
                     project = FALSE) |>
      addLegend(
        position  = "bottomright",
        pal       = pal,
        values    = c(-3, 3),
        title     = paste0(input$index_type, "-12<br>", input$date_choice),
        labFormat = labelFormat(digits = 1)
      )
  })

  # ----------------------------------------------------------
  # Click handler
  # ----------------------------------------------------------
  clicked_point <- reactiveVal(NULL)

  observeEvent(input$drought_map_click, {
    click <- input$drought_map_click
    clicked_point(data.frame(x = click$lng, y = click$lat))
    leafletProxy("drought_map") |>
      clearMarkers() |>
      addMarkers(
        lng   = click$lng,
        lat   = click$lat,
        popup = paste0("Lon: ", round(click$lng, 2),
                       "<br>Lat: ", round(click$lat, 2))
      )
  })

  # ----------------------------------------------------------
  # Extract time series at clicked point
  # ----------------------------------------------------------
 clicked_ts <- reactive({
    req(clicked_point())
    stack <- selected_stack()
    pt    <- clicked_point()

    vals <- terra::extract(stack, matrix(c(pt$x, pt$y), ncol = 2))
    
    # vals[1,] includes an ID column first, so -1 removes it
    # match length to all_dates to avoid size mismatch
    v <- as.numeric(vals[1, -1])
    n <- min(length(v), length(all_dates))

    tibble(
      date  = all_dates[1:n],
      value = v[1:n]
    )
  })

  # ----------------------------------------------------------
  # Time series plot
  # ----------------------------------------------------------
  output$ts_plot <- renderPlot({
    req(clicked_point())
    ts <- clicked_ts()

    if (all(is.na(ts$value))) {
      return(
        ggplot() +
          annotate("text", x = 0.5, y = 0.5,
                   label = "Location outside data grid\nClick inside Nigeria",
                   size = 5, colour = "grey50") +
          theme_void()
      )
    }

    ggplot(ts, aes(date, value)) +
      geom_hline(yintercept =  0,    colour = "grey60", linewidth = 0.4) +
      geom_hline(yintercept = -1.0,  colour = "orange",  linetype = "dashed", linewidth = 0.6) +
      geom_hline(yintercept = -1.5,  colour = "red3",    linetype = "dashed", linewidth = 0.6) +
      geom_hline(yintercept = -2.0,  colour = "darkred", linetype = "dashed", linewidth = 0.8) +
      geom_line(colour = "steelblue", linewidth = 0.55) +
      # Shade only the part of the curve below each threshold
      geom_ribbon(aes(ymin = pmin(value, -1), ymax = -1),
                  fill = "orange",  alpha = 0.25) +
      geom_ribbon(aes(ymin = pmin(value, -2), ymax = -2),
                  fill = "darkred", alpha = 0.30) +
      annotate("text", x = min(ts$date), y = -1.08,
               label = "Moderate (−1.0)", hjust = 0, size = 3, colour = "orange") +
      annotate("text", x = min(ts$date), y = -2.08,
               label = "Extreme (−2.0)",  hjust = 0, size = 3, colour = "darkred") +
      scale_x_date(date_breaks = "5 years", date_labels = "%Y") +
      labs(
        x     = NULL,
        y     = paste0(input$index_type, "-12"),
        title = paste0(input$index_type, "-12 at Lon: ",
                       round(clicked_point()$x, 2),
                       ", Lat: ", round(clicked_point()$y, 2))
      ) +
      theme_minimal(base_size = 12)
  })

  # ----------------------------------------------------------
  # Hotspot choropleth — filled by state
  # ----------------------------------------------------------
  output$hotspot_plot <- renderPlot({
    index_key <- tolower(input$index_type)
    thresh    <- input$threshold
    metric    <- input$hotspot_metric

    admin_df <- hotspot_by_admin[[index_key]][[thresh]]

    # Join to spatial boundary
    admin_sf <- nigeria_l1 |>
      left_join(admin_df, by = c("NAME_1" = "state_name"))

    # Friendly metric label
    metric_label <- switch(metric,
      persistence   = "Persistence\n(fraction of months)",
      n_events      = "Number of\ndrought events",
      mean_severity = "Mean severity\n(index units)"
    )

    # Title label
    thresh_label <- switch(thresh,
      moderate = "Moderate (≤ −1.0)",
      severe   = "Severe (≤ −1.5)",
      extreme  = "Extreme (≤ −2.0)"
    )

    ggplot(admin_sf) +
      geom_sf(aes(fill = .data[[metric]]),
              colour = "white", linewidth = 0.3) +
      scale_fill_viridis_c(
        name      = metric_label,
        option    = "inferno",
        direction = -1,
        na.value  = "grey85"
      ) +
      labs(
        title    = paste0(input$index_type, "-12 | ", thresh_label),
        subtitle = paste0(metric_label |> gsub("\n", " ", x = _),
                          " | 1981–2024 | CRU TS v4.09")
      ) +
      theme_void(base_size = 11) +
      theme(
        legend.position  = "bottom",
        legend.key.width = unit(1.8, "cm"),
        plot.title       = element_text(face = "bold", size = 12),
        plot.subtitle    = element_text(size = 9, colour = "grey50")
      )
  })
}

# ============================================================
shinyApp(ui, server)
