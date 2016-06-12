# R script to create a graph of code changes per day vs time
#
# usage: Rscript create_graph.R data.csv "description of git repo"
#

# Tweakable Parameters
minimum_commits                  <- 10
n_days_to_filter                 <- 11
minimum_changes_for_author_label <- 1000
author_label_cex                 <- 0.4
points_character                 <- 20
points_character_cex             <- 0.05

# Parse command line options
args <- commandArgs( trailingOnly = TRUE )
filename = args[1]
git_repo = args[2]

# Fetch data
d <- read.csv( filename, head = TRUE, sep=":" )

d$date <- as.Date( d$date, "%Y-%m-%d" )

nauthors <- length( unique( d$author ) )

dd <- vector( mode="list", length=nauthors )
ic <- 1
for ( author in unique( d$author ) ) {
    ii <- d$author == author
    xx <- d$date[ii]

    # Skip users with few commits
    if( length(xx) < minimum_commits ) next

    # Median changes per day
    median_changes <- median( diff( d$total[ii] ) )

    # d$total still may have wild jumps if we missed any
    # changes that should obviously be ignored
    # ( rename directories, include javascript libraries, perltidy whole files, etc )
    # diff of d$total gives us a vector of changes per day
    # runmed(...,11) of the result applies an 11-day median filter to smooth it out
    # cumsum adds it all up, so it is a cumulative vector like the original d$total
    yy <- cumsum( runmed( diff( d$total[ii] ), n_days_to_filter ) )

    # xx[-1] to shorten xx by one, so it is same length as yy
    dd[[ic]]$x      <- xx[-1]
    dd[[ic]]$y      <- yy
    dd[[ic]]$author <- author
    dd[[ic]]$cpd    <- median_changes

    ic <- ic + 1
}

filled <- !unlist( lapply( dd, is.null ) )
iauthors <- ( 1:nauthors )[filled]
C <- rainbow( length( iauthors ) )

ymax <- 0
for ( i in c( iauthors ) ) {
    ymax <- max( ymax, max( dd[[i]]$y ) )
}

# leave room for labels
xlimit <- c(min(d$date), max(d$date) + 1.5*365)

# Round up to nearest 0.1 of the significant digit
significant <- floor( log10( ymax ) ) - 1
ymax <- 10**significant * ceiling( ymax / 10**significant )

pdf(file="git_rockstar.pdf")

plot( xlimit, c(NaN,NaN),
      ylim=c(1,ymax),
      ylab="",
      xlab="",
      type="l",
      col="#FFFFFFFF",
      main=paste("Code Changes on ", git_repo ,sep="")
      sub=sprintf("%1d Non-Merge Commits", length(d$total)),
      yaxt="n",
      xaxt="n",
)

xt  <- seq(0, ymax, 10**significant)
xtl <- xt
for ( i in c(1:length(xt)) ) {
    value <- xt[i]
    label <- ifelse( value == 0, "0",
             ifelse( value < 10^3,  value,
             ifelse( value < 10^6,  paste( value/10^3,  "k", sep="" ),
             ifelse( value < 10^9,  paste( value/10^6,  "m", sep="" ),
             ifelse( value < 10^12, paste( value/10^12, "b", sep="" ),
             ifelse( value < 10^15, paste( value/10^15, "t", sep="" ), "Infinity"
    ))))))
    xtl[i] <- label
}

# Custom y-ticks and labels, las=2 means tick labels perpendicular to axis
axis(2, at=xt, labels=xtl, las=2)

years <- as.numeric( substr( as.character( xlimit ), 1, 4 ) )
# Ensure there will be at least 2 tick marks
years[2] = ifelse( years[2] == years[1], years[2] + 1, years[2] )

yvec <- years[1]:years[2]
yt <- as.Date( paste( yvec, "-01-01", sep='' ) )
axis(1, at=yt, labels=yvec, las=2)

for ( i in c(iauthors) ) {
    xx     <- dd[[i]]$x
    yy     <- dd[[i]]$y
    author <- dd[[i]]$author
    cpd    <- dd[[i]]$cpd

    # col sets the color, pch sets the marker, cex alters the marker size
    points( xx, yy, col=C[i], pch=points_character, cex=points_character_cex )
    
    # Do not bother labelling authors with fewer than 1000 total changes.
    if (max(yy) > minimum_changes_for_author_label ) {
        # pos=4 means align left
        text( xx[ length(xx) ], yy[ length(yy) ],
             sprintf("%s [ %s cpd ]", author, cpd),
             pos=4,
             cex=author_label_cex,
             col=C[ic])
    }
}

dev.off()
