# Get command-line arguments
tf <- commandArgs(trailingOnly = TRUE)



source("utils.R")
# ?get_targeting
# get_targeting("41459763029", timeframe = "LAST_90_DAYS")
# debugonce(get_targeting)

library(httr)
library(tidyverse)
library(lubridate)

sets <- jsonlite::fromJSON("settings.json")

title_txt <- read_lines("_site/_quarto.yml")
title_txt[which(str_detect(title_txt, "title"))] <-  glue::glue('  title: "{sets$dashboard}"')
write_lines(title_txt, "_site/_quarto.yml")

# tf <- Sys.getenv("TIMEFRAME")c
tf <- "30"
# print(tf)

jb <- get_targeting("7860876103", timeframe = glue::glue("LAST_90_DAYS"))

new_ds <- jb %>% arrange(ds) %>% slice(1) %>% pull(ds)
# new_ds <- "2023-08-11"

latest_elex <- readRDS(paste0("data/election_dat", tf, ".rds"))

latest_ds <- latest_elex %>% arrange(ds) %>% slice(1) %>% pull(ds)



tstamp <- Sys.time()

write_lines(lubridate::as_date(tstamp), "tstamp.txt")

# - name: Set timeframe 
# run: |
#   echo "::set-env name=TIMEFRAME::30 Timeframe"



wtm_data <- read_csv("data/wtm-advertisers-sk-2023-09-13T19_30_21.053Z.csv") %>% #names
  filter(countries.alpha2 == "sk") %>% 
  select(page_id = advertisers_platforms.advertiser_platform_ref,
         page_name = name, party = entities.short_name)  %>%
  mutate(page_id = as.character(page_id)) %>%
  filter(!(party %in% c("Ost", "Méd", "Vlá"))) %>%
filter(str_detect(page_name, "Kaufland", negate = T))



#View
  # count(party, sort = T)  %>%
  # mutate(party = case_when(
  #   str_detect(party, "VVD") ~ "VVD",
  #   str_detect(party, "\\bCDA\\b") ~ "CDA",
  #   str_detect(party, "PvdA|Jonge Socialisten") ~ "PvdA",
  #   str_detect(party, "D66|Jonge Democraten") ~ "D66",
  #   str_detect(party, "GroenLinks|GL") ~ "GroenLinks",
  #   str_detect(party, "ChristenUnie|CU") ~ "ChristenUnie",
  #   str_detect(party, "\\bSP\\b") ~ "SP",
  #   str_detect(party, "FvD|FVD|Forum voor Democratie") ~ "FvD",
  #   str_detect(party, "50Plus|50PLUS") ~ "50PLUS",
  #   str_detect(party, "\\bSGP\\b") ~ "SGP",
  #   str_detect(party, "PvdD|Partij voor de Dieren") ~ "PvdD",
  #   str_detect(party, "PVV") ~ "PVV",
  #   str_detect(party, "DENK") ~ "DENK",
  #   str_detect(party, "Volt|VOLT") ~ "Volt Nederland",
  #   str_detect(party, "BIJ1|BiJ") ~ "BIJ1",
  #   str_detect(party, "BVNL") ~ "BVNL",
  #   str_detect(party, "Ja21") ~ "JA21",
  #   str_detect(page_name, "Alliantie") ~ "Alliantie",
  #   str_detect(page_name, "Partij voor de Dieren") ~ "PvdD",
  #   str_detect(page_name, "Christine Govaert") ~ "BBB",
  #   str_detect(page_name, "BVNL|Belang van Nederland") ~ "BVNL",
  #   T ~ party
  # ))

# wtm_data %>%
#   filter(party == "ZL")
# 
wtm_data %>%
  count(party, sort = T)

# 338750440106782

all_dat <- #read_csv("nl_advertisers.csv") %>%
  # mutate(page_id = as.character(page_id)) %>%
  # bind_rows(internal_page_ids) %>%
  bind_rows(wtm_data) %>%
  # bind_rows(rep) %>%
  # bind_rows(more_data %>% mutate(source = "new")) %>%
  distinct(page_id, .keep_all = T) %>%
  add_count(page_name, sort  =T) %>%
  mutate(remove_em = n >= 2 & str_ends(page_id, "0")) %>%
  filter(!remove_em) %>%
  # filter(n >= 2) %>%
  # filter(n >= 2 & str_ends(page_id, "0", negate = T)) %>%
  select(-n)  


saveRDS(all_dat, "data/all_dat.rds")

scraper <- function(.x, time = tf) {
  
  # print(paste0(.x$page_name,": ", round(which(internal_page_ids$page_id == .x$page_id)/nrow(internal_page_ids)*100, 2)))
  
  fin <- get_targeting(.x$page_id, timeframe = glue::glue("LAST_{time}_DAYS")) %>%
    mutate(tstamp = tstamp)
  
  if(nrow(fin)!=0){
    path <- paste0(glue::glue("targeting/{time}/"),.x$page_id, ".rds")
    # if(file.exists(path)){
    #   ol <- read_rds(path)
    #
    #   saveRDS(fin %>% bind_rows(ol), file = path)
    # } else {
    
    saveRDS(fin, file = path)
    # }
  } else {
   fin <- tibble(internal_id = .x$page_id, no_data = T) %>%
      mutate(tstamp = tstamp)
  }
  
  # print(nrow(fin))
  # })
  return(fin)
  
}

scraper <- possibly(scraper, otherwise = NULL, quiet = F)


# if(F){
#     # dir("provincies/7", full.names
# }
# da30 <- readRDS("data/election_dat30.rds")
# da7 <- readRDS("data/election_dat7.rds")

if(new_ds == latest_ds){
  print(glue::glue("New DS: {new_ds}: Old DS: {latest_ds}"))
  
  ### save seperately
  enddat <- all_dat %>% 
    arrange(page_id) %>%
    # slice(1:150) %>% 
    filter(!(page_id %in% latest_elex$page_id)) %>% 
    split(1:nrow(.)) %>%
    map_dfr_progress(scraper) 
  
  if(nrow(enddat)==0){
    election_dat <- latest_elex
  } else {
    
    print(glue::glue("New DS: {new_ds}: Old DS: {latest_ds} 2"))
    
    
    election_dat  <- enddat %>%
      mutate_at(vars(contains("total_spend_formatted")), ~parse_number(as.character(.x))) %>% 
      rename(page_id = internal_id) %>%
      left_join(all_dat) %>% 
      bind_rows(latest_elex)    
    
    current_date <- paste0("historic/",  as.character(new_ds), "/", tf)
    
    saveRDS(election_dat, file = paste0(current_date, ".rds"))
  }
  

  } else {
  
  ### save seperately
  election_dat <- all_dat %>% 
    arrange(page_id) %>%
    # slice(1:50) %>%
    split(1:nrow(.)) %>%
    map_dfr_progress(scraper)  %>%
    mutate_at(vars(contains("total_spend_formatted")), ~parse_number(as.character(.x))) %>% 
    rename(page_id = internal_id)  %>%
    left_join(all_dat) 
  
  dir.create(paste0("historic/",  as.character(new_ds)), recursive = T)
  current_date <- paste0("historic/",  as.character(new_ds), "/", tf)
  
  saveRDS(election_dat, file = paste0(current_date, ".rds"))
  
  
}

saveRDS(election_dat, paste0("data/election_dat", tf, ".rds"))

##### combinations ####


minimum_date <- dir("historic", recursive = T) %>%
  keep(~str_detect(.x, paste0(tf, "\\.rds"))) %>% 
  str_remove("/.*") %>%
  as.Date() %>%
  min(na.rm = T)


if("ds" %in% names(election_dat) ){
  
  try({
    
    
    
    latest_ds <- election_dat %>% arrange(ds) %>% slice(1) %>% pull(ds) %>% as.Date()
    
    begintf <- as.Date(latest_ds) - lubridate::days(tf)
    
    date_vector <- vector()
    current_date <- latest_ds
    index <- 1
    
    while(current_date > minimum_date) {
      
      date_vector[index] <- current_date
      
      current_date <- current_date - lubridate::days(tf)
      
      index <- index + 1
      
    }
    
    if(length(date_vector != 0)){
      
      
      combined_dat <- paste0("historic/", as_date(date_vector), "/", tf, ".rds") %>%
        map_dfr(~{
          if(!file.exists(.x)){
            return(tibble(ds = as.character(begintf), missing_report = T))
          } else {
            readRDS(.x)
          }
          
        })
      
      saveRDS(combined_dat, file= paste0("data/combined_dat", tf,  ".rds"))
      
      aggr <- combined_dat  %>%
        # mutate(total_spend_formatted = ifelse(!is.character(total_spend_formatted), as.character(total_spend_formatted), total_spend_formatted, )) %>% 
        mutate(total_spend = readr::parse_number(as.character(total_spend_formatted))) %>%
        mutate(total_spend = ifelse(total_spend == 50, 50, total_spend)) %>%
        mutate(total_spend = total_spend * total_spend_pct) %>%
        group_by(page_id, value, type, location_type, detailed_type, custom_audience_type, is_exclusion) %>%
        summarize(total_spend = sum(total_spend),
                  num_ads = sum(num_ads),
                  num_obfuscated = sum(num_obfuscated)) %>%
        ungroup()
      
      saveRDS(aggr, file = paste0("data/election_dat_aggr", tf,  ".rds"))
      
      
      
      
    }
    
    
    
    if(new_ds == latest_ds){
      
      unlink(paste0("targeting/", tf), recursive = T, force = T)
      
      dir.create(paste0("targeting/", tf))
      
      write_lines("_", paste0("targeting/", tf, "/", "_"))
      
    }
    
  })

}

# source("start.R")
