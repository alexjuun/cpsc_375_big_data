
library(dplyr)
library(tidyverse)
library(kableExtra)
library(modelr)
library(ggplot2)

#As I mentioned to professor, I think that training data is not really enough for the 2022. Therefore, I will load the two excel files which are of 2022 and 2023 from databank. 

# Loading the File 
covid <- read.csv("owid-covid-data.csv")
pop_2022 <- readxl::read_excel("population_train.xlsx")
pop_2023 <- readxl::read_excel("population_valid.xlsx")

# iso code which has 3 length
covid <- covid %>%
  filter(nchar(iso_code) == 3)

# having the train and test data which is valid_data. Removing Series name to prevent the multiple rows from future pivot wider.
pop_train<- pop_2022 %>% dplyr::select(-c("Series Name"))
pop_valid<- pop_2023 %>% dplyr::select(-c("Series Name"))

# Do pivot wider to have each country with the variables will be as an column each
pop_valid <- pop_valid %>%
  pivot_wider(names_from = "Series Code", values_from = "2023 [YR2023]")
pop_train <- pop_train %>%
  pivot_wider(names_from = "Series Code", values_from = "2022 [YR2022]")

# Data cleaning removing some unnecessary rows.
pop_valid<- pop_valid %>% dplyr::select(-c("NA")) %>%
  slice(1:(n() - 3))
pop_train<- pop_train %>% dplyr::select(-c("NA")) %>%
  slice(1:(n() - 3))

# need to numeric to have logical operator
pop_valid <- pop_valid %>%
  mutate(SP.POP.TOTL = as.numeric(as.character(SP.POP.TOTL)))
pop_train <- pop_train %>%
  mutate(SP.POP.TOTL = as.numeric(as.character(SP.POP.TOTL)))

# having the population more than 1000000
pop_valid <- pop_valid %>%
  filter(!is.na(SP.POP.TOTL),      
         SP.POP.TOTL >= 1000000)

pop_train <- pop_train %>%
  filter(!is.na(SP.POP.TOTL),     
         SP.POP.TOTL >= 1000000)

# Before join the data spliting the covid file to train and test data
covid_valid <- covid %>% filter(date >= as.Date("2023-01-01"))

covid_train <- covid %>% filter(date >= as.Date("2022-01-01")) %>%
  filter(date < as.Date("2023-01-01"))

# In order to have a prediction use lag function to have a prediction.
covid_valid <- covid_valid %>%
  mutate(date = as.Date(date) - 14,
         new_deaths_smoothed_2wk = new_deaths_smoothed,
         new_deaths_smoothed = lag(new_deaths_smoothed, 14))

covid_train <- covid_train %>%
  mutate(date = as.Date(date) - 14,
         new_deaths_smoothed_2wk = new_deaths_smoothed,
         new_deaths_smoothed = lag(new_deaths_smoothed, 14))

# Keep all data but selecting the important variables
covid_valid <- covid_valid %>%
  select(iso_code, date, new_deaths_smoothed, new_deaths_smoothed_2wk, population, everything())
covid_train <- covid_train %>%
  select(iso_code, date, new_deaths_smoothed, new_deaths_smoothed_2wk, population, everything())

# Doing inner join to have same iso_code and country code
final_valid <- inner_join(covid_valid, pop_valid, by = c("iso_code" = "Country Code"))
final_train <- inner_join(covid_train, pop_train, by = c("iso_code" = "Country Code"))

# Doing some data wriangling for future calulation
final_valid <- final_valid %>%
  mutate(SP.POP.80UP.FE = as.numeric(as.character(SP.POP.80UP.FE)),
         SP.POP.80UP.MA = as.numeric(as.character(SP.POP.80UP.MA)),
         SP.URB.TOTL = as.numeric(as.character(SP.URB.TOTL)),
         SP.POP.TOTL = as.numeric(as.character(SP.POP.TOTL)))

final_train <- final_train %>%
  mutate(SP.POP.80UP.FE = as.numeric(as.character(SP.POP.80UP.FE)),
         SP.POP.80UP.MA = as.numeric(as.character(SP.POP.80UP.MA)),
         SP.URB.TOTL = as.numeric(as.character(SP.URB.TOTL)),
         SP.POP.TOTL = as.numeric(as.character(SP.POP.TOTL)))

# Having Three variables transfrom
final_valid <- final_valid %>%
  mutate(cardiovasc_deaths = cardiovasc_death_rate * population)
final_train <- final_train %>%
  mutate(cardiovasc_deaths = cardiovasc_death_rate * population)

final_valid <- final_valid %>%
  mutate(elderly_population_percentage = ((SP.POP.80UP.FE + SP.POP.80UP.MA) / SP.POP.TOTL) * 100)
final_train <- final_train %>%
  mutate(elderly_population_percentage = ((SP.POP.80UP.FE + SP.POP.80UP.MA) / SP.POP.TOTL) * 100)

final_valid <- final_valid %>%
  mutate(urban_population_percentage = (SP.URB.TOTL / SP.POP.TOTL) * 100)
final_train <- final_train %>%
  mutate(urban_population_percentage = (SP.URB.TOTL / SP.POP.TOTL) * 100)

# January to June 30 of testing data
final_valid <- final_valid %>%
  filter(as.Date("2023-01-01") <= date & date <= as.Date("2023-06-30"))

# just checking the NA values from testing data to exclude the predictors who have lots of NA values. 
na_counts <- sapply(final_valid, function(x) sum(is.na(x)))
print(na_counts)

# Comprehensive Model
model_1 <- lm(new_deaths_smoothed_2wk ~ new_cases_smoothed + total_cases + icu_patients + total_vaccinations + people_fully_vaccinated + gdp_per_capita + urban_population_percentage + life_expectancy + elderly_population_percentage, data = final_train)
summary(model_1)

# Social Economic Model
model_2 <- lm(new_deaths_smoothed_2wk ~ gdp_per_capita + extreme_poverty + population_density + urban_population_percentage + human_development_index, data = final_train)
summary(model_2)

# Vaccination related Model
model_3 <- lm(new_deaths_smoothed_2wk ~ total_vaccinations + people_vaccinated + people_fully_vaccinated + total_boosters + new_vaccinations_smoothed, data = final_train)
summary(model_3)


#Health Infrastructure model
model_4 <- lm(new_deaths_smoothed_2wk ~ population + hospital_beds_per_thousand + icu_patients + hosp_patients + handwashing_facilities, data = final_train)
summary(model_4)

rmse_1 <- rmse(model = model_1, data = final_valid)
rmse_2 <- rmse(model = model_2, data = final_valid)
rmse_3 <- rmse(model = model_3, data = final_valid)
rmse_4 <- rmse(model = model_4, data = final_valid)

cat("Overall RMSE of model 1:", rmse_1, "\n")
cat("Overall RMSE of model 2:", rmse_2, "\n")
cat("Overall RMSE of model 3:", rmse_3, "\n")
cat("Overall RMSE of model 4:", rmse_4, "\n")


# Having RMSE of testing data from Model 1 which I think it is the best model.
country_rmse <- final_valid %>%
  group_by(iso_code) %>%
  summarise(location = first(location),
            population = first(population),
            RMSE = rmse(model= model_1, data=cur_data())
  ) %>% 
  arrange(RMSE)
print(country_rmse)

# preparing the data to grouping by iso_code
plot_1 <- final_valid %>%
  group_by(iso_code) %>%
  summarise(
    new_deaths_smoothed_2wk = last(new_deaths_smoothed_2wk), 
    new_cases_smoothed = last(new_cases_smoothed)
  )

# Plot the new_cases_smoothed, new_deaths_smoothed_2wk
ggplot(plot_1, aes(x = new_cases_smoothed, y = new_deaths_smoothed_2wk)) +
  geom_point() +
  labs(title = "Scatterplot of New Cases vs. Future New Deaths",
       x = "New Cases Smoothed",
       y = "New Deaths Smoothed 2 Weeks Ahead")

# preparing the data to grouping by iso_code
plot_2 <- final_valid %>%
  group_by(iso_code) %>%
  summarise(
    new_deaths_smoothed = last(new_deaths_smoothed),
    total_population_over_80 = last(SP.POP.80UP.FE + SP.POP.80UP.MA)
  )

# Plot the total more than 80s, new_deaths_smoothed
ggplot(final_valid, aes(x = (SP.POP.80UP.FE + SP.POP.80UP.MA), y = new_deaths_smoothed)) +
  geom_point() +
  labs(title = "Scatterplot of Population Over 80 vs. New Deaths",
       x = "Population Over 80",
       y = "New Deaths Smoothed")

# Having all 4 RMSE and R^2
data.frame(Model = c("Model 1", "Model 2", "Model 3", "Model 4"),
           RMSE = c(rmse_1, rmse_2, rmse_3, rmse_4),
           R2 = c(summary(model_1)$r.squared, summary(model_2)$r.squared,
                  summary(model_3)$r.squared, summary(model_4)$r.squared))

# Top 20 country
top_20_countries_by_population <- country_rmse %>%
  arrange(desc(population)) %>%
  slice_head(n = 20)  

print(top_20_countries_by_population)





