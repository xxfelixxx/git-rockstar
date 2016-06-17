# R script to create a graph of code changes per day vs time
#
# usage: Rscript create_graph.R data.csv "description of git repo"
#

# Tweakable Parameters
minimum_commits                  <- 10
n_days_to_filter                 <- 30
top_n_authors                    <- 20
author_label_cex                 <- 0.4
points_character                 <- 20
points_character_cex             <- 0.05
maximum_x_labels                 <- 20
maximum_y_labels                 <- 20

# Parse command line options
args <- commandArgs( trailingOnly = TRUE )
filename = args[1]
git_repo_title = args[2]

if ( is.na( filename) || is.na( git_repo_title ) ) {
    write("usage: Rscript create_graph.R data.csv 'description of git repo'", stdout())
    quit(save="no")
}

# Remove quotes
git_repo_title <- gsub("'", "", git_repo_title)

# Fetch data, quote="" disable quoting, fixing the 'EOF within quoted string' message
# http://stackoverflow.com/questions/17414776/read-csv-warning-eof-within-quoted-string-prevents-complete-reading-of-file
d <- read.csv( filename, head = TRUE, sep="\t", quote="" )

d$date <- as.Date( d$date, "%Y-%m-%d" )

unique_authors <- unique( d$author )
nauthors <- length( unique_authors )

max_commit_days <- 0
for ( author in unique_authors ) {
    commit_days <- length( which( d$author == author ))
    max_commit_days <- max( max_commit_days, commit_days )
}

dd <- vector( mode="list", length=nauthors )
ic <- 1

# For new repos, show all commits (at least 2 for diff to work)
minimum_commits <- ifelse( max_commit_days < minimum_commits, 2, minimum_commits )

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

all_authors <- c()
ymax <- 0
for ( i in c( iauthors ) ) {
    max_author <- max( dd[[i]]$y )
    all_authors <- c(all_authors, max_author)
    ymax <- max( ymax, max_author )
}

minimum_changes_for_author_label <- (sort(all_authors, decreasing=TRUE))[top_n_authors]
minimum_changes_for_author_label <- if( is.na(minimum_changes_for_author_label) ) 0 else minimum_changes_for_author_label

# leave room for labels
dmin <- min(d$date)
dmax <- max(d$date)
xlimit <- c(dmin, dmax + 0.20 * diff( c( as.numeric(dmin), as.numeric(dmax) ) ) )

# Round up to nearest 0.1 of the significant digit
significant <- floor( log10( ymax ) ) - 1
ymax <- 10**significant * ceiling( ymax / 10**significant )

svg(file="git_rockstar.svg")

plot( xlimit, c(NaN,NaN),
      ylim=c(1,ymax),
      ylab="",
      xlab="",
      type="l",
      col="#FFFFFFFF",
      main=git_repo_title,
      sub=sprintf("%1d Non-Merge Commits", length(d$total)),
      yaxt="n",
      xaxt="n",
)

xt  <- seq(0, ymax, 10**significant)
# Fix if too many labels
if ( length(xt) > maximum_y_labels) {
    skip <- ceiling( length(xt) / maximum_y_labels)
    xt <- xt[ seq( 1, length(xt), skip) ]
}
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
# Fix if too many labels
if ( length(yvec) > maximum_x_labels) {
    skip <- ceiling( length(yvec) / maximum_x_labels)
    yvec <- yvec[ seq( 1, length(yvec), skip) ]
}

# No more than 1 year into the future
yymax <- as.numeric( substr( as.character( dmax ), 1, 4 ) ) + 1
yvec <- yvec[ yvec <= yymax ]
yt <- as.Date( paste( yvec, "-01-01", sep='' ) )
axis(1, at=yt, labels=yvec, las=2)

# Plot the author time series
for ( i in c(iauthors) ) {
    xx     <- dd[[i]]$x
    yy     <- dd[[i]]$y

    # col sets the color, pch sets the marker, cex alters the marker size
    points( xx, yy, col=C[i], pch=points_character, cex=points_character_cex )
}

# Text labels show go over the dots
for ( i in c(iauthors) ) {
    xx     <- dd[[i]]$x
    yy     <- dd[[i]]$y
    author <- dd[[i]]$author
    cpd    <- dd[[i]]$cpd
    color  <- C[i]

    # TODO: Switch for color labels vs black labels
    color  <- "#000000"
    
    # Do not bother labelling authors with fewer than 1000 total changes.
    if (max(yy) >= minimum_changes_for_author_label ) {
        # pos=4 means align left
        text( xx[ length(xx) ], yy[ length(yy) ],
             sprintf("%s [ %s mcpd ]", author, cpd),
             pos=4,
             cex=author_label_cex,
             col=color)
    }
}

# pos=3 means above
text( mean(xlimit), 0.99*ymax, "mcpd - median changes per day", pos=3, cex=0.7)

dev.off()
