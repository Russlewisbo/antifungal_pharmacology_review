# Regenerates figures/fig_penetration.png
# Licensed agents are scored against Felton et al. 2014 (Clin Microbiol Rev 27:68-88);
# agents marked with a dagger are not covered by that review.
library(ggplot2)

levels_lab <- c("Negligible", "Low", "Moderate", "High")
symbols <- c(Negligible = "\u2013", Low = "\u2193", Moderate = "\u2022", High = "\u2191")
fills <- c(Negligible = "#8a95a5", Low = "#d0d7e2", Moderate = "#91c8a8", High = "#1b7a4e")

sites <- c("CSF /\nbrain parenchyma", "Vitreous /\naqueous humour", "Urine\n(active drug)",
           "Epithelial lining\nfluid / lung", "Deep tissue\n(liver, spleen, kidney)")

m <- rbind(
  "Amphotericin B\ndeoxycholate"        = c(1, 1, 2, 1, 3),
  "Liposomal\namphotericin B"           = c(1, 1, 2, 2, 3),
  "Flucytosine"                         = c(3, 2, 3, 2, 2),
  "Fluconazole"                         = c(3, 2, 3, 2, 2),
  "Voriconazole"                        = c(2, 2, 0, 3, 2),
  "Posaconazole"                        = c(1, 1, 0, 2, 2),
  "Isavuconazole\u2020"                 = c(1, 1, 0, 2, 2),
  "Echinocandins /\nrezafungin\u2020"   = c(1, 1, 0, 2, 3),
  "Ibrexafungerp\u2020"                 = c(1, 1, 1, 2, 3),
  "Fosmanogepix\u2020"                  = c(2, 1, 2, 2, 3),
  "Olorofim\u2020"                      = c(2, 1, 1, 2, 2),
  "Opelconazole\u2020\n(inhaled)"       = c(0, 0, 0, 3, 0)
)

d <- data.frame(
  agent = factor(rep(rownames(m), times = ncol(m)), levels = rev(rownames(m))),
  site = factor(rep(sites, each = nrow(m)), levels = sites),
  level = factor(levels_lab[as.vector(m) + 1], levels = levels_lab)
)
d$sym <- symbols[as.character(d$level)]
d$txt <- ifelse(d$level %in% c("Negligible", "High"), "white", "#1b2733")

p <- ggplot(d, aes(site, agent, fill = level)) +
  geom_tile(colour = "white", linewidth = 1.2) +
  geom_text(aes(label = sym, colour = txt), size = 5) +
  scale_colour_identity() +
  scale_fill_manual(
    values = fills, name = NULL,
    labels = paste(symbols, levels_lab)
  ) +
  scale_x_discrete(position = "bottom") +
  labs(
    title = "Penetration into anatomically privileged sites drives agent choice",
    x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 13) +
  theme(
    panel.grid = element_blank(),
    axis.text.x = element_text(angle = 35, hjust = 1, size = 11),
    axis.text.y = element_text(size = 11),
    plot.title = element_text(hjust = 0, size = 16),
    plot.title.position = "plot",
    legend.position = "right"
  )

ggsave("figures/fig_penetration.png", p, width = 9.5, height = 6.2, dpi = 200, bg = "white")
