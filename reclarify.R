# Workflow for automated analysis of LDIR data
# Joey O'Dell Feb 2022 - No Rights Reserved (CC0)

# load required packages for the analysis
library("tidyverse")
library("readxl")
library("pivottabler")
library("dplyr")
library("openxlsx")

# Input the sample characteristics here
# SampleID <- dlgInput("Please enter Sample ID", default="")$res #- user-driven input
SampleID <- "S_04_01"
pcAnalysed <- 0.08    # as decimal percent to 2 d.places
massSed <- 0.03079    # in kilograms

# the next two lines control the size class in microns for the output
SizeClasses <- c(0,10,50,100,200,500,900)
SizeTags <- c("(0,10]", "(10,50]", "(50,100]", "(100,200]", "(200,500]", "(500,900]")

# setup variables for our workflow
LDIRFile <- paste("raw/",SampleID,".xlsx",sep="")
OutputFile <- paste("output/",SampleID,"_output.xlsx",sep="")

# load spectral libraries
# for all excel imports we'll use '.name_repair = universal' to keep things safe
df.SpecLib_Hereon <- read_excel("ref/HereonMPLib.xlsx",
                             sheet = "HereonMPLib",
                             .name_repair = "universal")

df.SpecLib_MPstarter <- read_excel("ref/MPStarter1_0.xlsx",
                                 sheet = "MPStarter1_0",
                                 .name_repair = "universal")

# we'll now bind these into one library to simplfy searching 
df.SpecLib_bind <- bind_rows(df.SpecLib_Hereon, df.SpecLib_MPstarter)
# And remove any duplicate spectra names
df.SpecLib <- df.SpecLib_bind %>% distinct(Spectra, .keep_all = TRUE)

# Load LDIR data 
df.LDIRData <- read_excel(LDIRFile, 
                      sheet = "Particles",
                      .name_repair = "universal")

# Filter LDIR data to remove hit rate below 0.8
df.data_step1 <- dplyr::filter(df.LDIRData, Quality>=0.8)
# Filter again to remove rejected results
df.data_filtered <- dplyr::filter(df.data_step1, Is.Valid=="true")
# joining the filtered data table with the spectra library
df.data_joined <- merge(df.data_filtered, df.SpecLib, by.x = "Identification", by.y = "Spectra", all.x = TRUE)
df.data_joined %>% group_by(Grouping)

# binning data by predetermined size classes
df.data_binned <- df.data_joined %>% mutate(diameter.binned = cut(Diameter..μm., breaks=SizeClasses))

# add IsPlastic flag to enable grouping in table
df.data_categorised <- df.data_binned %>% mutate(IsPlastic = ifelse(Grouping!="Natural components",1,0))

# create pivot table
# using guidance from http://www.pivottabler.org.uk/

pt <- PivotTable$new()
pt$addData(df.data_categorised) 
pt$addColumnDataGroups("diameter.binned")
pt$addRowDataGroups("Grouping")
PlasticFilter <- PivotFilters$new(pt, variableName="IsPlastic", values=1)
pt$defineCalculation(calculationName="Total", summariseExpression="n()", noDataValue=0)
pt$defineCalculation(calculationName="MPs", summariseExpression="n()", filters=PlasticFilter)
pt$evaluatePivot()
pt$renderPivot()

# calculate summary statistics
stat.totalMPs <- sum(df.data_categorised$IsPlastic == 1)
stat.extrapMPs <- stat.totalMPs / pcAnalysed
stat.MPsperkilo <- stat.totalMPs / massSed

# create data frame for the summary statistics
df.SummaryStats <- data.frame(Characteristic=c("Sample ID", "Share Analysed","Kg Sediment","Total MPs","Extrapolated MPs", "MPs per Kilogram"),
                              Value=c(SampleID, pcAnalysed, massSed, stat.totalMPs, stat.extrapMPs, stat.MPsperkilo))

# export to excel workbook
# create workbook with ourselves as the author
wb <- createWorkbook(creator = Sys.getenv("USERNAME"))
# add two worksheets, one for the pivottable, and another for the summary results
addWorksheet(wb, SampleID)
addWorksheet(wb, "Statistics")
# write the pivot table to the first worksheet
pt$writeToExcelWorksheet(wb=wb, wsName=SampleID, 
                         topRowNumber=1, leftMostColumnNumber=1, 
                         applyStyles=TRUE, mapStylesFromCSS=TRUE)
# write the summary statistics data frame to the second worksheet
writeData(wb=wb, "Statistics", df.SummaryStats, startCol = 1, startRow = 1
)

# export the whole file
saveWorkbook(wb, file = OutputFile, overwrite = TRUE)