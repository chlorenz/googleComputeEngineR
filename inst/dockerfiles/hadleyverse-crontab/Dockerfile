FROM rocker/hadleyverse
MAINTAINER Mark Edmondson (r@sunholo.com)

# install cron and R package dependencies
RUN apt-get update && apt-get install -y \
    cron \
    nano \
    ## clean up
    && apt-get clean \ 
    && rm -rf /var/lib/apt/lists/ \ 
    && rm -rf /tmp/downloaded_packages/ /tmp/*.rds
    
## Install packages from CRAN
RUN install2.r --error \ 
    -r 'http://cran.rstudio.com' \
    googleAuthR shinyFiles \
    ## install Github packages
    && Rscript -e "devtools::install_github(c('bnosac/cronR'))" \
    ## clean up
    && rm -rf /tmp/downloaded_packages/ /tmp/*.rds \

## Start cron
RUN service cron start