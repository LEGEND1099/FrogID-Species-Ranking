# STAT5003 REPORT-03: visual-only refresh of existing saved modelling evidence.
# Usage: Rscript R/reporting/03_batch12_visuals.R
# Does NOT source any model training script, change splits or train classifiers.
# Reads aggregate CSV outputs and 0.5-degree binned geography (in memory only).

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(ggplot2)
})
stopifnot(file.exists('renv.lock'), dir.exists('outputs/tables'))
tab <- 'outputs/tables'
fig <- 'outputs/figures'

read_checked <- function(filename, needed) {
  path <- file.path(tab, filename)
  if (!file.exists(path)) stop('Missing input: ', path)
  x <- read_csv(path, show_col_types = FALSE, progress = FALSE)
  if (!all(needed %in% names(x))) {
    stop('Missing fields in ', path, ': ', paste(setdiff(needed, names(x)), collapse = ', '))
  }
  x
}

C <- list(blue = '#27679C', blue_light = '#A9C7DE', orange = '#D87537',
          slate = '#96A3AF', grey = '#D5DCE3', text = '#263645',
          red = '#E0A39D', cream = '#F9F5ED', green = '#80B8A1')
models <- c('random_forest', 'xgboost', 'pca_knn', 'pca_lda', 'elastic_net')
labels <- c(random_forest='Random Forest',xgboost='XGBoost',
            pca_knn='PCA-kNN',pca_lda='PCA-LDA',elastic_net='Elastic-net')
model_cols <- c('Random Forest'=C$blue,'XGBoost'=C$orange,
                'PCA-kNN'=C$slate,'PCA-LDA'='#ADB7C1','Elastic-net'='#C4CCD3')
report_theme <- function(base_size=11) {
  theme_minimal(base_size = base_size) +
    theme(
      text=element_text(colour=C$text),
      panel.grid.minor=element_blank(),
      panel.grid.major.y=element_blank(),
      plot.title=element_text(face='bold',size=base_size+2,margin=margin(b=6)),
      plot.subtitle=element_text(size=base_size-1,colour='#506270',margin=margin(b=10)),
      axis.title=element_text(size=base_size-1),
      legend.position='bottom',plot.margin=margin(13,14,13,14)
    )
}
save <- function(p,name,width,height,dpi=200) {
  path <- file.path(fig,name)
  ggsave(path,p,width=width,height=height,dpi=dpi,units='in',bg='white',limitsize=FALSE)
  cat('Saved: ',path,'\n',sep='')
}

# 1. Cohort imbalance using identical support across 3 spatial folds.
prevalence <- read_checked('report_species_equity_prevalence.csv',
                           c('scientificName','total_support','rare_six')) %>%
  arrange(total_support)
stopifnot(nrow(prevalence)==18L,sum(prevalence$total_support)==242600)
prevalence <- prevalence %>% mutate(
  scientificName=factor(scientificName,levels=scientificName),
  dominance=ifelse(total_support>=40000,'Two most recorded','Other species'))
p <- ggplot(prevalence,aes(x=scientificName,y=total_support,fill=dominance)) +
  geom_col(width=.74) + coord_flip() +
  scale_fill_manual(values=c('Two most recorded'=C$orange,'Other species'=C$blue),
                    name=NULL) +
  scale_y_continuous(labels=function(x) format(x,big.mark=',',trim=TRUE),
                     expand=expansion(mult=c(0,.07))) +
  labs(title='FrogID recordings are strongly class-imbalanced',
       subtitle='242,600 complete-case events; two most recorded species comprise 53.4%',
       x=NULL,y='Recording events') + report_theme(10)
save(p,'report_v1_species_frequency.png',8.6,5.5)

# 2. Validation schematic: conceptual cells, no fitted models or true geography.
grid <- expand.grid(x=1:9,y=1:4)
grid$group <- ifelse((grid$x+2*grid$y)%%5==0,'Assess','Develop')
a <- grid %>% mutate(regime='Spatial: whole 0.5° cells') %>%
  transmute(x,y,regime,xmin=x-.46,xmax=x+.46,ymin=y-.44,ymax=y+.44,group)
# For event-level random CV each cell may contribute to both partitions;
# illustrate by splitting a drawn cell into a development and assessment half.
b <- bind_rows(
 grid %>% mutate(regime='Random: events can share cells',group='Develop') %>%
   transmute(x,y,regime,xmin=x-.46,xmax=x+.02,ymin=y-.44,ymax=y+.44,group),
 grid %>% mutate(regime='Random: events can share cells',group='Assess') %>%
   transmute(x,y,regime,xmin=x+.02,xmax=x+.46,ymin=y-.44,ymax=y+.44,group))
p <- ggplot(bind_rows(a,b)) +
  geom_rect(aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=group),
            colour='white',linewidth=.25) +
  facet_wrap(~regime,ncol=2) +
  scale_fill_manual(values=c(Develop=C$blue,Assess=C$orange),name=NULL) +
  scale_x_continuous(breaks=NULL,expand=c(0,0)) +
  scale_y_continuous(breaks=NULL,expand=c(0,0)) +
  coord_equal() + labs(title='Two evaluation questions, the same frozen cohort',
     subtitle='Schematic only: blue = development, orange = held-out assessment') +
  report_theme(10)+theme(panel.grid=element_blank(),strip.text=element_text(face='bold'),
                        axis.title=element_blank(),panel.spacing=grid::unit(1.5,'lines'))
save(p,'report_v1_validation_schematic.png',8.6,3.1)

# 3. Reporting comparison: main model columns, consistent model colours.
all_summary <- read_checked('report_model_summary.csv',
                            c('model','feature_set','regime','macro_f1_mean','macro_f1_sd'))
sum_m4 <- all_summary %>% filter(model %in% models,feature_set=='M4',
                                regime %in% c('random','spatial')) %>%
  mutate(model_label=factor(labels[model],levels=rev(labels[models])),
         regime=factor(regime,levels=c('random','spatial'),
                       labels=c('Random folds','Spatial folds')))
stopifnot(nrow(sum_m4)==10)
p <- ggplot(sum_m4,aes(x=model_label,y=macro_f1_mean,fill=model_label))+
  geom_col(width=.66) +
  geom_errorbar(aes(ymin=pmax(0,macro_f1_mean-macro_f1_sd),
                    ymax=macro_f1_mean+macro_f1_sd),width=.18,linewidth=.36) +
  geom_text(aes(label=sprintf('%.3f',macro_f1_mean)),hjust=-.16,size=3.05)+
  coord_flip(ylim=c(0,.79),clip='off') + facet_wrap(~regime,nrow=1)+
  scale_fill_manual(values=model_cols,drop=FALSE,guide='none')+
  scale_y_continuous(breaks=seq(0,.8,.2))+
  labs(title='Random validation overstates geographic transfer',
       subtitle='M4: 3-fold mean Macro-F1; whiskers show between-fold SD',
       x=NULL,y='Macro-F1 (higher is better)') + report_theme(10) +
  theme(strip.text=element_text(face='bold'))
save(p,'report_v1_m4_comparison.png',9.4,4.15)

# 4. M4 minus M3: paired comparisons with same model colours.
effects <- read_checked('report_m3_m4_effect.csv',
                        c('model','regime','delta_macro_f1_mean','folds_m4_better')) %>%
  filter(model %in% models) %>%
  mutate(model_label=factor(labels[model],levels=rev(labels[models])),
         regime=factor(regime,levels=c('random','spatial'),
                       labels=c('Random folds','Spatial folds')))
stopifnot(nrow(effects)==10)
p <- ggplot(effects,aes(y=model_label,x=delta_macro_f1_mean,colour=model_label))+
  geom_vline(xintercept=0,linetype='dashed',colour='#9FA6AD')+
  geom_segment(aes(x=0,xend=delta_macro_f1_mean,yend=model_label),linewidth=.7,alpha=.65)+
  geom_point(size=3.1)+
  geom_text(aes(label=sprintf('%+.3f',delta_macro_f1_mean)),hjust=ifelse(effects$delta_macro_f1_mean>=0,-.18,1.18),size=2.9,colour=C$text)+
  facet_wrap(~regime,nrow=1)+
  scale_colour_manual(values=model_cols,guide='none')+
  scale_x_continuous(limits=c(-.025,.066),breaks=c(-.02,0,.02,.04,.06))+
  labs(title='Adding coordinates has model-dependent benefits',
       subtitle='Paired M4 minus M3 mean Macro-F1 on identical outer folds',
       x='Change in Macro-F1',y=NULL)+report_theme(10)+
  theme(strip.text=element_text(face='bold'))
save(p,'report_v1_coordinate_effect.png',9.4,4.05)

# 5. Softer red-neutral-green species F1 heatmap; print values for accessibility.
equity <- read_checked('report_species_equity_by_species.csv',
                       c('model','scientificName','mean_f1','rare_six','total_support')) %>%
  filter(model %in% models)
stopifnot(nrow(equity)==90)
prevalence_names <- as.character(prevalence$scientificName)
equity <- equity %>% mutate(
  model_label=factor(labels[model],levels=labels[models]),
  species_label=factor(ifelse(rare_six,paste0('* ',scientificName),scientificName),
    levels=rev(ifelse(prevalence$rare_six,paste0('* ',prevalence_names),prevalence_names))))
p <- ggplot(equity,aes(x=model_label,y=species_label,fill=mean_f1))+
  geom_tile(colour='white',linewidth=.55)+
  geom_text(aes(label=sprintf('%.2f',mean_f1)),size=3.0,colour=C$text)+
  scale_fill_gradient2(low=C$red,mid=C$cream,high=C$green,
                       midpoint=.32,limits=c(0,.80),name='Mean F1')+
  labs(title='Species coverage separates the near-tied tree models',
       subtitle='M4 spatial mean species F1 across three folds; * marks six least-recorded species',
       x=NULL,y=NULL)+report_theme(10)+
  theme(panel.grid=element_blank(),legend.position='right',
        axis.text.x=element_text(angle=18,hjust=1,size=9.4),axis.text.y=element_text(size=9))
save(p,'report_v1_species_equity_heatmap.png',9.4,7.7)

# 6. All 18 coarse geographic recording footprints, arranged 3 rows x 6 columns.
# Read-only plotting: no model training, fold or prediction changes.
# Optional maps package adds an outline. Without it the map remains an honest,
# labelled tile view, not an inaccurate fabricated coastline.
cohort_path <- 'data/processed/frog_primary_multiclass.rds'
if (file.exists(cohort_path)) {
  cohort <- readRDS(cohort_path)
  needed <- c('scientificName','decimalLatitude','decimalLongitude')
  if (!all(needed %in% names(cohort))) stop('Geography data missing fields')
  geo <- as_tibble(cohort) %>%
    transmute(scientificName=as.character(scientificName),
      lon=(floor(decimalLongitude/.5)+.5)*.5,
      lat=(floor(decimalLatitude/.5)+.5)*.5) %>%
    count(scientificName,lon,lat,name='events') %>%
    mutate(scientificName=factor(scientificName,levels=sort(unique(scientificName))))
  p <- ggplot() +
    geom_tile(data=geo,aes(lon,lat,fill=log10(events)),
               width=.5,height=.5,alpha=.98)+
    facet_wrap(~scientificName, ncol=6,
      labeller=labeller(scientificName=label_wrap_gen(width=20)))+
    coord_quickmap(xlim=c(111,155),ylim=c(-45,-9),expand=FALSE)+
    scale_fill_gradientn(colours=c('#347BAF','#29A3BE','#F3BB63','#E8792D','#B44B25'),
                         values=scales::rescale(c(0,1,2,3,4)),
                         limits=c(0,4),oob=scales::squish,
                         name='Recording count',breaks=c(0,1,2,3,4),
                         labels=c('1','10','100','1,000','10,000'))+
    labs(title='Observed species footprints differ by region',
         subtitle='Recording counts per 0.5° cell; 18 target species; not biological ranges',
         x=NULL,y=NULL)+report_theme(10)+
    theme(panel.grid=element_blank(),axis.text=element_blank(),
          strip.text=element_text(size=9.35,face='italic',colour=C$text,
                                  lineheight=.94),
          panel.spacing=grid::unit(.46,'lines'),
          legend.position='right')
  # Public-domain Natural Earth simplified Australian coastline bundled locally.
  # This is reference cartography, not FrogID event-location data.
  coastline_path <- 'R/reporting/assets/australia_outline.csv'
  if (!file.exists(coastline_path)) stop('Missing coastline outline: ', coastline_path)
  australia <- read_csv(coastline_path, show_col_types = FALSE)
  p <- p + geom_path(data=australia,
    aes(x=long,y=lat,group=group),inherit.aes=FALSE,
    colour='#354957',linewidth=.28)
  save(p,'report_v1_geographic_footprints.png',13.0,5.35,230)
} else {
  stop('Missing original cohort for geography figure: ',cohort_path)
}

cat('\nREPORT-03 PASSED. No model training or saved model results changed.\n')
