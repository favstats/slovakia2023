
# https://adstransparency.google.com/advertiser/AR09355418985304162305?political&region=NL&preset-date=Last%207%20days
# install.packages("pacman")
pacman::p_load(tidyverse, RSelenium, binman, wdman)

wdman::gecko()
wdman::selenium()

dir.create("data/ggl", recursive = T)

download.file(url = "https://storage.googleapis.com/political-csv/google-political-ads-transparency-bundle.zip", destfile = "data/ggl/ggl.zip", method = "curl")

unzip("data/ggl/ggl.zip", exdir = "data/ggl")

# google_political_ads_advertiser_stats %>% 
#   filter(str_detect(Regions, "NL")) %>% View()

Sys.sleep(10)

gglstats <- vroom::vroom("data/ggl/google-political-ads-creative-stats.csv")

ggl_spend <- gglstats   %>%
  mutate(Date_Range_Start = lubridate::ymd(Date_Range_Start)) %>%
  filter(Date_Range_Start >= as.Date("2023-08-01")) %>% 
  filter(str_detect(Regions, "SK")) %>% 
  distinct(Advertiser_ID, Advertiser_Name, .keep_all = T) %>%
  mutate(party1 = case_when(
    str_detect(Advertiser_Name, "HLAS") ~ "HLAS",
    str_detect(Advertiser_Name, "SME RODINA") ~ "SR",
    str_detect(Advertiser_Name, "Progresívne Slovensko") ~ "PS",
    str_detect(Advertiser_Name, "Ideamedia") ~ "Mod",
    str_detect(Advertiser_Name, "OĽANO") ~ "OLaNO",
    str_detect(Advertiser_Name, "Demokrati") ~ "D",
    str_detect(Advertiser_Name, "Sloboda a Solidarita") ~ "SASKA",
    str_detect(Advertiser_Name, "SMER") ~ "SMER",
    str_detect(Advertiser_Name, "Szövetség") ~ "A-S",
    str_detect(Advertiser_Name, "Slovenská národná strana") ~ "SNS",
    str_detect(Advertiser_Name, "Promiseo") ~ "KDH",
    str_detect(Advertiser_Name, "ZA ĽUDÍ") ~ "ZL",
    T ~ NA_character_
  )) %>%
  filter(!(str_detect(Advertiser_Name, "Slovenská demokratická|FDP|Gleichheitspartei|Nieuw-Vlaamse|SP Digital LLC|MURRAY|REVOLT|Angelenos Against Higher Property Taxes|ITALIA|Volt Deutschland"))) %>%
  drop_na(party1) 

saveRDS(ggl_spend, "data/ggl_spend.rds")

# gglstats %>% 
#   filter(str_detect(Regions, "NL")) %>% View()

# port <- netstat::free_port()
podf <- sample(4000L:5000L,1)
rD <- rsDriver(browser = "firefox"
                    ,chromever=NULL
                ,check = F
                ,port = podf
                ,verbose = T
)


library(rvest)

remDr <- rD$client

retrieve_spend_daily <- function(id, the_date, cntry = "SK") {

  # id <- "AR18091944865565769729"
  url <- glue::glue("https://adstransparency.google.com/advertiser/{id}?political&region={cntry}&start-date={the_date}&end-date={the_date}&topic=political")
  remDr$navigate(url)

  Sys.sleep(1)

  thth <- remDr$getPageSource() %>% .[[1]] %>% read_html()

  Sys.sleep(3)

  root3 <- "/html/body/div[3]"
  root5 <- "/html/body/div[5]"
  ending <- "/root/advertiser-page/political-tabs/div/material-tab-strip/div/tab-button[2]/material-ripple"

  try({
    insights <<- remDr$findElement(value = paste0(root5, ending))
    it_worked <- T
  })

  if(!exists("it_worked")){

    print("throwed an error")

    try({
      insights <<- remDr$findElement(value = paste0(root3, ending))

    })

    root <- root3

  } else {
    root <- root5
  }

  print("click now")
  insights$clickElement()

  Sys.sleep(3)

  pp <- remDr$getPageSource() %>% .[[1]] %>% read_html()

  ending_eur <- "/root/advertiser-page/insights-grid/div/div/overview/widget/div[3]/div[1]/div"
  ending_ads <- "/root/advertiser-page/insights-grid/div/div/overview/widget/div[3]/div[3]/div"

  print("retrieve numbers")
  # try({
  eur_amount <- pp %>%
    html_elements(xpath = paste0(root, ending_eur)) %>%
    html_text()

  num_ads <- pp %>%
    html_elements(xpath = paste0(root, ending_ads)) %>%
    html_text()

  # })

  fin <- tibble(advertiser_id = id, eur_amount, num_ads, date = the_date)

  print(fin)

  return(fin)

}

# daily_spending <- readRDS("data/daily_spending.rds")
# Apr 17, 2023 - May 16, 2023
  # 13 February 2023
timelines <- seq.Date(as.Date("2023-08-01"), lubridate::today()-lubridate::days(1), by = "day")

try({
  
  daily_spending_old <- readRDS("data/ggl_daily_spending.rds")
})
if(!exists("daily_spending_old")) daily_spending_old <- tibble()



  daily_spending <- expand_grid(unique(ggl_spend$Advertiser_ID), timelines) %>%
    set_names(c("advertiser_id", "timelines")) %>%
    anti_join(daily_spending_old %>% select(advertiser_id, timelines = date)) %>% 
    split(1:nrow(.)) %>%
    map_dfr_progress(~{retrieve_spend_daily(.x$advertiser_id, .x$timelines)})

  missings <- expand_grid(unique(ggl_spend$Advertiser_ID), timelines) %>%
    set_names(c("advertiser_id", "timelines")) %>%
    anti_join(daily_spending %>% rename(timelines = date))  %>%
    split(1:nrow(.)) %>%
    map_dfr_progress(~{retrieve_spend_daily(.x$advertiser_id, .x$timelines)})
  
  
saveRDS(daily_spending %>% bind_rows(missings) %>% bind_rows(daily_spending_old) %>% distinct(), file = "data/ggl_daily_spending.rds")


dates <- read_csv("data/dates.csv")

retrieve_spend_custom <- function(id, from, to, cntry = "SK") {
  
  # id <- "AR18091944865565769729"
  url <- glue::glue("https://adstransparency.google.com/advertiser/{id}?political&region={cntry}&start-date={from}&end-date={to}")
  remDr$navigate(url)
  
  Sys.sleep(1)
  
  thth <- remDr$getPageSource() %>% .[[1]] %>% read_html()
  
  Sys.sleep(3)
  
  root3 <- "/html/body/div[3]"
  root5 <- "/html/body/div[5]"
  ending <- "/root/advertiser-page/political-tabs/div/material-tab-strip/div/tab-button[2]/material-ripple"
  
  try({
    insights <<- remDr$findElement(value = paste0(root5, ending))
    it_worked <- T
  })
  
  if(!exists("it_worked")){
    
    print("throwed an error")
    
    try({
      insights <<- remDr$findElement(value = paste0(root3, ending))
      
    })
    
    root <- root3
    
  } else {
    root <- root5
  }
  
  print("click now")
  insights$clickElement()
  
  Sys.sleep(3)
  
  pp <- remDr$getPageSource() %>% .[[1]] %>% read_html()
  
  ending_eur <- "/root/advertiser-page/insights-grid/div/div/overview/widget/div[3]/div[1]/div"
  ending_ads <- "/root/advertiser-page/insights-grid/div/div/overview/widget/div[3]/div[3]/div"
  
  print("retrieve numbers")
  # try({
  eur_amount <- pp %>%
    html_elements(xpath = paste0(root, ending_eur)) %>%
    html_text()
  
  num_ads <- pp %>%
    html_elements(xpath = paste0(root, ending_ads)) %>%
    html_text()
  
  # })
  
  
  ending_type <- "/root/advertiser-page/insights-grid/div/div/ad-formats/widget/div[4]"
  
  
  type_spend <<- pp %>%
    html_elements(xpath = paste0(root, ending_type)) %>%
    html_children() %>%
    html_text() %>%
    tibble(raww = .) %>%
    mutate(type = str_to_lower(str_extract(raww, "Video|Text|Image"))) %>%
    mutate(raww = str_remove_all(raww, "Video|Text|Image") %>% str_remove_all("%|\\(.*\\)") %>% as.numeric) %>%
    pivot_wider(names_from = type, values_from = raww)
  
  
  fin <- tibble(advertiser_id = id, eur_amount, num_ads, from, to)
  
  if(nrow(type_spend)!=0){
    fin <- fin %>%
      bind_cols(type_spend)
  }
  
  
  
  print(fin)
  
  return(fin %>% mutate_all(as.character))
  
}

ggl_sel_sp_old <- readRDS("data/ggl_sel_sp.rds")

if(!any(dates$begin30 == ggl_sel_sp_old$from)){
  
  ggl_sel_sp <- unique(ggl_spend$Advertiser_ID) %>%
    # .[22] %>%
    map_dfr_progress(~{retrieve_spend_custom(.x, dates$begin30, dates$fin)})
  
  
  
  misssss <- ggl_sel_sp$advertiser_id %>% setdiff(unique(ggl_spend$Advertiser_ID), .)
  # filter(!(advertiser_id %in% unique(ggl_spend$Advertiser_ID)))
  
  # ggl_sel_sp <- ggl_sel_sp %>%
  # bind_rows(fvd) %>%
  # distinct(advertiser_id, .keep_all = T)
  
  # fvd <- retrieve_spend("AR03397262231409262593")
  fvd <- misssss %>%
    # .[22] %>%
    map_dfr_progress(~{retrieve_spend_custom(.x, dates$begin30, dates$fin)})
  
  ggl_sel_sp <- ggl_sel_sp %>%
    bind_rows(fvd) %>%
    distinct(advertiser_id, .keep_all = T)
  
  
  saveRDS(ggl_sel_sp , file = "data/ggl_sel_sp.rds")
  
  ggl_sel_sp7_old <- readRDS("data/ggl_sel_sp7.rds")
  
  
  ggl_sel_sp7 <- unique(ggl_spend$Advertiser_ID) %>%
    # .[22] %>%
    map_dfr_progress(~{retrieve_spend_custom(.x, dates$begin7, dates$fin)})
  
  misssss7 <- ggl_sel_sp7$advertiser_id %>% setdiff(unique(ggl_spend$Advertiser_ID), .)
  
  # misss <- retrieve_spend_custom("AR14725485108811268097", dates$begin7, dates$fin)
  
  misss <- misssss7 %>%
    # .[22] %>%
    map_dfr_progress(~{retrieve_spend_custom(.x, dates$begin7, dates$fin)})
  
  
  saveRDS(ggl_sel_sp7 %>% bind_rows(misss) %>% #bind_rows(ggl_sel_sp7_old) %>%
            distinct(advertiser_id, .keep_all = T), file = "data/ggl_sel_sp7.rds")
  
  
}

unlink("data/ggl", recursive = T, force = T)
# file.remove("data/ggl/google-political-ads-creative-stats.csv")







# ggl_sel_sp <- readRDS("data/ggl_sel_sp.rds")

tt_ads <- ggl_sel_sp %>%
  rename(Advertiser_ID = advertiser_id) %>%
  left_join(ggl_spend %>% distinct(Advertiser_ID, party1))  %>%
  # mutate(Date_Range_Start = lubridate::ymd(Date_Range_Start)) %>%
  # filter(Date_Range_Start >= as.Date("2023-02-05")) %>%
  group_by(party1) %>%
  summarize(total_num_ads = sum(as.numeric(num_ads))) %>%
  # count(party1, name = "total_num_ads") %>%
  mutate(total_num_ads = scales::comma(total_num_ads)) %>%
  pivot_wider(names_from = party1, values_from = total_num_ads) %>%
  mutate(party_col = "Number of Ads")


ttl_spn <- ggl_sel_sp %>%
  rename(Advertiser_ID = advertiser_id) %>%
  left_join(ggl_spend %>% distinct(Advertiser_ID, party1)) %>%
  mutate(Spend_EUR = readr::parse_number(str_remove(eur_amount, "\\."))) %>%
  group_by(party1) %>%
  summarize(Spend_EUR = sum(Spend_EUR)) %>%
  arrange(desc(Spend_EUR)) %>%
  select(party = party1, spend = Spend_EUR) %>%
  mutate(spend = scales::comma(spend)) %>%
  mutate(spend = paste0("€", spend)) %>%
  drop_na() %>%
  pivot_wider(names_from = party, values_from = spend) %>%
  mutate(party_col = "Total Spend")



tp_spnders <- ggl_sel_sp %>%
  rename(Advertiser_ID = advertiser_id) %>%
  left_join(ggl_spend %>% distinct(Advertiser_ID, party1, .keep_all = T) %>% select(Advertiser_ID, party1, Advertiser_Name)) %>%
  mutate(Spend_EUR = readr::parse_number(str_remove(eur_amount, "\\.")))   %>%
  group_by(Advertiser_Name, party1) %>%
  summarize(Spend_EUR = sum(Spend_EUR)) %>%
  ungroup() %>%
  group_by(party1) %>%
  arrange(desc(Spend_EUR)) %>%
  slice(1:3) %>%
  mutate(Spend_EUR = scales::comma(Spend_EUR)) %>%
  mutate(n_words = str_count(Advertiser_Name, " ")) %>%
  # mutate(lab = paste0(word(str_remove(page_name, "-"), 1,ifelse(n_words>=2, 3, 2), sep=" "), "<br>(€", total_spend_formatted, ")")) %>%
  mutate(lab = paste0(Advertiser_Name, " (€", Spend_EUR, ")")) %>%
  select(party1, lab) %>%
  drop_na() %>%
  summarize(lab = paste0("<br>", 1:n(), ". ", lab, collapse = "")) %>%
  pivot_wider(names_from = party1, values_from = lab) %>%
  mutate(party_col = "Top Spenders")

ggl_all <- tt_ads %>%
  bind_rows(tp_spnders) %>%
  bind_rows(ttl_spn) %>%
  t() %>%
  as.data.frame() %>%
  rownames_to_column("Coalizione/Partito") %>%
  set_names(.[nrow(.),] %>% as.character()) %>%
  slice(1:(n()-1))


saveRDS(ggl_all, file = "data/ggl_all.rds")






ggl_sel_sp7 <- ggl_sel_sp7 %>%
  filter(num_ads != "0") 

tt_ads <- ggl_sel_sp7 %>%
  rename(Advertiser_ID = advertiser_id) %>%
  left_join(ggl_spend %>% distinct(Advertiser_ID, party1))  %>%
  # mutate(Date_Range_Start = lubridate::ymd(Date_Range_Start)) %>%
  # filter(Date_Range_Start >= as.Date("2023-02-05")) %>%
  group_by(party1) %>%
  summarize(total_num_ads = sum(as.numeric(num_ads))) %>%
  # count(party1, name = "total_num_ads") %>%
  mutate(total_num_ads = scales::comma(total_num_ads)) %>%
  pivot_wider(names_from = party1, values_from = total_num_ads) %>%
  mutate(party_col = "Number of Ads")


ttl_spn <- ggl_sel_sp7 %>%
  rename(Advertiser_ID = advertiser_id) %>%
  left_join(ggl_spend %>% distinct(Advertiser_ID, party1)) %>%
  mutate(Spend_EUR = readr::parse_number(str_remove(eur_amount, "\\."))) %>%
  group_by(party1) %>%
  summarize(Spend_EUR = sum(Spend_EUR)) %>%
  arrange(desc(Spend_EUR)) %>%
  select(party = party1, spend = Spend_EUR) %>%
  mutate(spend = scales::comma(spend)) %>%
  mutate(spend = paste0("€", spend)) %>%
  drop_na() %>%
  pivot_wider(names_from = party, values_from = spend) %>%
  mutate(party_col = "Total Spend")



tp_spnders <- ggl_sel_sp7 %>%
  rename(Advertiser_ID = advertiser_id) %>%
  left_join(ggl_spend %>% distinct(Advertiser_ID, party1, .keep_all = T) %>% select(Advertiser_ID, party1, Advertiser_Name)) %>%
  mutate(Spend_EUR = readr::parse_number(str_remove(eur_amount, "\\.")))   %>%
  group_by(Advertiser_Name, party1) %>%
  summarize(Spend_EUR = sum(Spend_EUR)) %>%
  ungroup() %>%
  group_by(party1) %>%
  arrange(desc(Spend_EUR)) %>%
  slice(1:3) %>%
  mutate(Spend_EUR = scales::comma(Spend_EUR)) %>%
  mutate(n_words = str_count(Advertiser_Name, " ")) %>%
  # mutate(lab = paste0(word(str_remove(page_name, "-"), 1,ifelse(n_words>=2, 3, 2), sep=" "), "<br>(€", total_spend_formatted, ")")) %>%
  mutate(lab = paste0(Advertiser_Name, " (€", Spend_EUR, ")")) %>%
  select(party1, lab) %>%
  drop_na() %>%
  summarize(lab = paste0("<br>", 1:n(), ". ", lab, collapse = "")) %>%
  pivot_wider(names_from = party1, values_from = lab) %>%
  mutate(party_col = "Top Spenders")

ggl_all7 <- tt_ads %>%
  bind_rows(tp_spnders) %>%
  bind_rows(ttl_spn) %>%
  t() %>%
  as.data.frame() %>%
  rownames_to_column("Coalizione/Partito") %>%
  set_names(.[nrow(.),] %>% as.character()) %>%
  slice(1:(n()-1)) 


saveRDS(ggl_all7, file = "data/ggl_all7.rds")

