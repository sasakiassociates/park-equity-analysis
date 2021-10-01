### Install C bindings for geoda in R, must have Geoda installed on $PATH
### Pulled from here https://github.com/lixun910/rgeoda
### 10-16-2019

### Main Resource (v0.0.3): https://rgeoda.github.io/rgeoda-book/load-spatial-data.html
###v0.0.4: https://mybinder.org/v2/gh/lixun910/rgeoda_tutorial/v0.0.4

## Goal: Use the new rgdal library to loop through a bunch of shp files and perform a moran's i
## Note: rgeoda currently does not handle undefined values (nulls), convert nulls to 0s or remove these.



## Windows
install.packages('wkb')
#install.packages("https://github.com/lixun910/rgeoda/releases/download/nb/rgeoda_0.0.3.zip")
#library(devtools)
#install_github("lixun910/rgeoda") # This broke with the new version?
# Select yes to install RTools

# Or just install from source on computer - This worked the best
#install.packages("F:\\GeodaScript_Kai\\GeodaScript_Kai\\rgeoda_0.0.3.zip",repos=NULL,type="source")


## Load libs
library(wkb)
library(sp)
library(rgdal)
library(rgeoda)
library(sf)
library(dplyr)
library(tidyverse)



#------ Looping through Local Moran's I for shapefiles in a specific folder.

## Set working directory where projected shapefiles are located
setwd("C:\\Users\\klau\\Desktop\\ParksEqProj\\UALevel_Zscore\\Inputs")

## List the files - for looping

path = getwd() #Store path - gets the working directory and set it as the variable titled path 
output_path = "C:\\Users\\klau\\Desktop\\ParksEqProj\\UALevel_Zscore\\Outputs"
sumstats_path = "C:\\Users\\klau\\Desktop\\ParksEqProj\\UALevel_Zscore\\SummaryStats"

shp_names <- dir(path,pattern="\\.shp$")  #The dir() function takes a path and searches with the pattern (which is a regular expression) in that location - produces a vector of files that end with shp
shp_names
csv_names <- str_remove(shp_names,pattern=".shp")
csv_names

## Helper function to create missing cluster columns
#https://stackoverflow.com/questions/45857787/adding-column-if-it-does-not-exist

fncols <- function(data, cname) {
  add <-cname[!cname%in%names(data)]

  if(length(add)!=0) data[add] <- as.numeric(0)
  data
}

  
##------------------------------------------UNIVARIATE-----------------------------------------

## Local Moran's I loop

for (i in 1:length(shp_names)) { # Loop syntax is for (i in list) {do this[i]}
  
  #--------------Load file, add z-score, cap to 95%---------------#
  # Reference: https://stackoverflow.com/questions/6148050/creating-z-scores
  ## Load file
  sf <- st_read(paste0(path,"/",shp_names[i])) # read the shapefile, return sf object
  
  ## Add z-score column, and z-score percent rank 0 - 1
  sf_z <- sf %>%
    mutate(prkacs_z = round(scale(PrkAcs_sum),6),
           prkacs_zp = round(percent_rank(prkacs_z),2))
  glimpse(sf_z)
  
  ## Identify prkacs_z where prkacs_zp = 0.95, using min b/c multiple values for 0.95 since this is rounded
  cap = min(sf_z$prkacs_z[sf_z$prkacs_zp==0.95])
  
  ## Change all prkacs_z above cap to cap in new column
  sf_z <- sf_z %>%
    mutate(prkacs_zcap = ifelse(prkacs_z >= cap, cap, prkacs_z))

  
  #---------------Local Moran's I in RGeoda---------------#
  
  ## Create geoda object from sf
  gda <- sf_to_geoda(sf_z)
  
  ## Create weights
  knn5_w <- knn_weights(gda, 5) 
  prkacs_zcap <- as.numeric(sf_z$prkacs_zcap)

  ## Local Moran Map - Cluster and significance map
  lisa <- local_moran(knn5_w, prkacs_zcap)
  lisa_colors <- lisa$GetColors() 
  lisa_labels <- lisa$GetLabels()
  lisa_clusters <- lisa$GetClusterIndicators()
  lisa_p <- lisa$GetPValues
  
  ### Save the shapefile results
  
  ## Append lisa results to original sf object
  sf_z <- sf_z %>%
    mutate(PrkAcs_CL = lisa_clusters,
           PrkAcs_CL2 = recode(PrkAcs_CL, 
                               "0" = "Insignificant",
                               "1" = "High-High",
                               "2" = "Low-Low",
                               "3" = "Low-High",
                               "4" = "High-Low"))
  
  #sf_z$PrkAcs_CL <- lisa_clusters # Another way to add a single column

  ## Export sf object as shapefile
  st_write(sf_z, paste0(output_path, "/CL_", shp_names[i]))


  #---------------Summary Statistics---------------#
  
  ## Load data
  df <- data.frame(sf_z)
  glimpse(df)

  ## Select columns you want to summarize
  sel_cols <- c("UANAME", "UACE10", "S_agtotpop", "S_ratotpop", "S_white", "S_black", "S_asian", "S_native", "S_other", "S_hisp", "S_ag18", "S_ag1865", "S_agov65", "S_Pov", "PrkAcs_CL2", "PrkAcs_sum")
  df_sel <- df %>%
    select(!!sel_cols) 
  glimpse(df_sel)

  ## Summary tables
  
  sel_cols <- c("UANAME", "S_agtotpop", "S_ratotpop", "S_white", "S_black", "S_asian", "S_native", "S_other", "S_hisp", "S_ag18", "S_ag1865", "S_agov65", "S_Pov", "PrkAcs_CL2", "PrkAcs_sum")
  UA_NAME <- as.character(df[1,"UANAME"]) # Store UA name as a variable to add on in a column, CHANGE TO COLUMN NAME B/C DIFF COLUMN NUMBER IN EACH FILE FOR SOME REASON.... 
  UACE10_code <- as.character(df[1,"UACE10"]) # grabs value at row 1, column UANAME
  
  df_sum <- df_sel %>%
    select(!!sel_cols) %>%
    group_by(PrkAcs_CL2) %>%
    #summarise_at(sum_cols, sum, na.rm=TRUE) %>%
    summarise(#Place = Place_name,
              #Pl_GEOID = Pl_GEOID_code,
              UANAME = UA_NAME,
              UACE10 = UACE10_code,
              PrkAcs_avg = mean(PrkAcs_sum)*1000,
              PrkAcs_med = median(PrkAcs_sum)*1000,
              PrkAcs_max = max(PrkAcs_sum)*1000,
              PrkAcs_min = min(PrkAcs_sum)*1000,
              S_agtotpop = sum(S_agtotpop, na.rm=TRUE),
              S_ratotpop = sum(S_ratotpop, na.rm=TRUE),
              S_white = sum(S_white, na.rm=TRUE),
              S_black = sum(S_black, na.rm=TRUE),
              S_asian = sum(S_asian, na.rm=TRUE),
              S_native = sum(S_native, na.rm=TRUE),
              S_other = sum(S_other, na.rm=TRUE),
              S_hisp = sum(S_hisp, na.rm = TRUE),
              S_ag18 = sum(S_ag18, na.rm = TRUE),
              S_ag1865 = sum(S_ag1865, na.rm = TRUE),
              S_agov65 = sum(S_agov65, na.rm = TRUE),
              S_Pov = sum(S_Pov, na.rm = TRUE)) %>%
    mutate_if(is.numeric, round, 3)
  glimpse(df_sum)
  
  df_sum <- df_sum %>%
    mutate(CLp_W = S_white/S_ratotpop*100,
           CLp_B = S_black/S_ratotpop*100,
           CLp_A = S_asian/S_ratotpop*100,
           CLp_Nat = S_native/S_ratotpop*100,
           CLp_Oth = S_other/S_ratotpop*100,
           CLp_Hisp = S_hisp/S_ratotpop*100,
           CLp_ag18 = S_ag18/S_agtotpop*100,
           CLp_ag1865 = S_ag1865/S_agtotpop*100,
           CLp_agov65 = S_agov65/S_agtotpop*100,
           CLp_pov = S_Pov/S_agtotpop*100) %>%
    mutate_if(is.numeric, round, 2)
  glimpse(df_sum)
  
  ## Export df_sum as csv file
  write_csv(df_sum, paste0(sumstats_path, "/", csv_names[i], "_SumCluster", ".csv"))
  print("sumstats saved")
}


## -------- Just sum demog, importing sum cluster

## Set working directory

setwd("C:\\Users\\klau\\Desktop\\ParksEqProj\\UALevel_Zscore\\SummaryStats\\Inputs")

## List the files - for looping

path = getwd() #Store path - gets the working directory and set it as the variable titled path 
output_path = "C:\\Users\\klau\\Desktop\\ParksEqProj\\UALevel_Zscore\\SummaryStats\\Outputs"

csv_names <- dir(path,pattern="\\.csv$")  #The dir() function takes a path and searches with the pattern (which is a regular expression) in that location - produces a vector of files that end with shp
input_names <- str_remove(csv_names,pattern="_SumCluster.csv")
input_names

fncols <- function(data, cname) {
  add <-cname[!cname%in%names(data)]
  
  if(length(add)!=0) data[add] <- as.numeric(0)
  data
}

## Sum demog loop

for (i in 1:length(input_names)) { 
  
  ## Load file
  csv <- read.csv(paste0(path,"/",input_names[i],"_SumCluster.csv"))
  
  ## Load as data frame
  df <- data.frame(csv)
  glimpse(df)

  ## Total population for each demographic variable selected
  
  df_R <- df %>%
    summarise_if(is.integer, sum, na.rm=TRUE) %>%
    select(R_AgTotPop = S_agtotpop,
           R_RaTotPop = S_ratotpop,
           R_TotW = S_white,
           R_TotB = S_black,
           R_TotA = S_asian,
           R_TotNat = S_native,
           R_TotOth = S_other,
           R_TotHisp = S_hisp,
           R_Tot18 = S_ag18,
           R_Tot1865 = S_ag1865,
           R_Totov65 = S_agov65,
           R_TotPov = S_Pov) 
  
  glimpse(df_R)
  
  # % pop within each variable
  df_cols <- c("UANAME", "PrkAcs_CL2", "S_agtotpop", "S_ratotpop", "S_white", "S_black", "S_asian", "S_native", "S_other", "S_hisp", "S_ag18", "S_ag1865", "S_agov65", "S_Pov")  
  Rp_cols <- c("PrkAcs_CL2", "Rp_AgTotPop", "Rp_RaTotPop", "Rp_W", "Rp_B", "Rp_A", "Rp_Nat", "Rp_Oth", "Rp_Hisp", "Rp_Tot18", "Rp_Tot1865", "Rp_Totov65", "Rp_TotPov")
  Name <- df[1,2]
  
  df_Rp <- df %>%
    select(!!df_cols) %>%
    mutate(Rp_AgTotPop = S_agtotpop/df_R$R_AgTotPop*100,
          Rp_RaTotPop = S_ratotpop/df_R$R_RaTotPop*100,
          Rp_W = S_white/df_R$R_TotW*100,
          Rp_B = S_black/df_R$R_TotB*100,
          Rp_A = S_asian/df_R$R_TotA*100,
          Rp_Nat = S_native/df_R$R_TotNat*100,
          Rp_Oth = S_other/df_R$R_TotOth*100,
          Rp_Hisp = S_hisp/df_R$R_TotHisp*100,
          Rp_Tot18 = S_ag18/df_R$R_Tot18*100,
          Rp_Tot1865 = S_ag1865/df_R$R_Tot1865*100,
          Rp_Totov65 = S_agov65/df_R$R_Totov65*100,
          Rp_TotPov = S_Pov/df_R$R_TotPov*100) %>% 
    mutate_if(is.numeric, round, 2) %>%
    select(!!Rp_cols) %>%
    gather(Demographics, valname, -PrkAcs_CL2) %>%
    spread(PrkAcs_CL2,valname) %>%
    mutate(UANAME = Name)
      
  glimpse(df_Rp)
  
  
  # Add in missing cluster columns
  
  clustcols <- c("Insignificant", "High-High", "Low-Low", "Low-High", "High-Low")
  df_Rp <- fncols(df_Rp, clustcols)
  
  glimpse(df_Rp)
  
  # Re-order columns b/c OCD
  df_Rpfin <- df_Rp %>%
    select("UANAME", "Demographics", "Insignificant", "High-High", "Low-Low", "Low-High", "High-Low") # Reorder the columns
 
  glimpse(df_Rpfin)

  ## Export df_sum_p and df_Rp as two separate csv files
  write_csv(df_Rpfin, paste0(output_path, "/", input_names[i], "_SumDemog", ".csv"))

}


### ---------------BELOW IS FOR SINGLE SHAPEFILE

#------ Local Moran's I for individual shapefile - ESDA with rgeoda and sf
# set path, read shp
path <- "C:\\Users\\klau\\Desktop\\ParksEqProj\\Projected\\All_UA_Prj\\TEST\\Prj_UACE10_00280.shp"
sf <- st_read(path) # read the shapefile, return sf object
sf
#simply call plot() to render first 9 choropleth maps using the first 9 variables in the dataset
#plot(sf)

# create geoda object from sf
gda <- sf_to_geoda(sf)

# create weights
knn5_w <- knn_weights(gda, 5)
knn5_w
PrkAcs_sum <- as.numeric(sf$PrkAcs_sum)

# Local Moran Map - Cluster and significance map
lisa <- local_moran(knn5_w, PrkAcs_sum)
lisa_colors <- lisa$GetColors() 
lisa_labels <- lisa$GetLabels()
lisa_clusters <- lisa$GetClusterIndicators()
lisa_pvals <- lisa$GetPValues()

#Cluster Map
# plot(st_geometry(sf), 
#      col=sapply(lisa_clusters, function(x){return(lisa_colors[[x+1]])}), 
#      border = "#333333", lwd=0.1)
# title(main = "Local Moran Cluster Map")
# legend('bottomleft', legend = lisa_labels, fill = lisa_colors, border = "#eeeeee")
# 
# #Significance Map
# p_labels <- c("Not significant", "p <= 0.05", "p <= 0.01", "p <= 0.001")
# p_colors <- c("#eeeeee", "#84f576", "#53c53c", "#348124")
# plot(st_geometry(sf), 
#      col=sapply(lisa_p, function(x){
#        if (x <= 0.001) return(p_colors[4])
#        else if (x <= 0.01) return(p_colors[3])
#        else if (x <= 0.05) return (p_colors[2])
#        else return(p_colors[1])
#      }), 
#      border = "#333333", lwd=0.1)
# title(main = "Local Moran Signif. Map")
# legend('bottomleft', legend = p_labels, fill = p_colors, border = "#eeeeee")

## Save the results
# https://r-spatial.github.io/sf/articles/sf2.html

# Append lisa results to original sf object
sf$PrkAcs_CL <- lisa_clusters

# Export sf object as shapefile
output_path <- "C:\\Users\\klau\\Desktop\\ParksEqProj\\Projected\\All_UA_Prj\\TEST\\Results"
st_write(sf, paste0(output_path, "\\CL_UACE10_00199", ".shp"))


#------ Summary Statistics - calculating demographic % within each cluster

## Load libraries
library(dplyr)
library(tidyverse)


## Load data
df <- data.frame(sf)
#glimpse(df)


## Select columns you want to summarize
df_sel <- df %>%
  select(S_totpop17:S_hisp17B, S_PovCount, wppl_CL) %>% # Add Tot HU and HUnoveh_17B in final
  mutate(cluster = recode(wppl_CL, 
         "0" = "Insignificant",
         "1" = "High-High",
         "2" = "Low-Low",
         "3" = "Low-High",
         "4" = "High-Low")
         )  %>%
  glimpse()


## Take acreage/person cluster results, summarize counts of total pop/race/in poverty/housing units no veh, by cluster group

# For each value in CL, sum these variables: s_ttp17, S_wh17B, S_bl17B, S_sn17B, S_nt17B, S_th17B, S_hs17B, pov, S_totalHUnoveh, Total HU

df_sum <- df_sel %>%
  group_by(wppl_CL, cluster) %>%
  summarise_all(sum, na.rm=TRUE) %>%
  ungroup()
  

## With new variables, calculate total population using race
# Which % total makes more sense?  Different universes - total pop or HU vs. total of each subgroup
# 1. Total population within each cluster - this is already calculated from the summary counts above: X% of the pop in CL1 are X Race
# 2. Total count by race across all clusters: X% of the Asian pop is within CL1

df_R <- df_sum %>%
  summarise_if(is.double, sum, na.rm=TRUE) %>%
  select(R_TotPop = S_totpop17,
         R_TotW = S_white17B,
         R_TotB = S_black17B,
         R_TotA = S_asian17B,
         R_TotNat = S_nat17B,
         R_TotOth = S_other17B,
         R_TotHisp = S_hisp17B,
         R_TotPov = S_PovCount) ##Add R_TotHU and R_HUnoveh


## Calculate percentages
# 1. % pop within each cluster

df_sum_p <- df_sum %>%
  mutate(CLp_W = S_white17B/S_totpop17*100,
         CLp_B = S_black17B/S_totpop17*100,
         CLp_A = S_asian17B/S_totpop17*100,
         CLp_Nat = S_nat17B/S_totpop17*100,
         CLp_Oth = S_other17B/S_totpop17*100,
         CLp_Hisp = S_hisp17B/S_totpop17*100,
         CLp_Pov = S_PovCount/S_totpop17*100) # CLp_HUnoveh <- HUnoveh/Tot_HU*100

# 2. % pop within each variable

df_Rp <- df_sum %>%
  mutate(Rp_TotPop = S_totpop17/df_R$R_TotPop*100,
         Rp_W = S_white17B/df_R$R_TotW*100,
         Rp_B = S_black17B/df_R$R_TotB*100,
         Rp_A = S_asian17B/df_R$R_TotA*100,
         Rp_Nat = S_nat17B/df_R$R_TotNat*100,
         Rp_Oth = S_other17B/df_R$R_TotOth*100,
         Rp_Hisp = S_hisp17B/df_R$R_TotHisp*100,
         Rp_Pov = S_PovCount/df_R$R_TotPov*100) %>% # Rp_HUnoveh <- HUnoveh/R_TotHUnoveh*100
  select(cluster, Rp_TotPop:Rp_Pov) %>%
  gather(Demographics, valname, -cluster) %>%
  spread(cluster,valname) %>%
  select(Demographics, "Insignificant", "High-high", "Low-Low", "Low-High", "High-Low")

## Export df_sum_p and df_Rp as two separate csv files
write_csv(df_sum_p, path = "df_sum_p.csv")
write_csv(df_Rp, path = "df_Rp.csv")