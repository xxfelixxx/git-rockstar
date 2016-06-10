args <- commandArgs(trailingOnly = TRUE)
filename = args[1]

d <- read.csv(filename, head = TRUE, sep=":")

d$date <- as.Date(d$date, "%Y-%m-%d")

pdf(file="git_rockstar.pdf")
# leave room for labels
xlimit <- c(min(d$date), max(d$date) + 2*365)
# arbitrary, but allows good comparison between best/worst
ymax <- 100000

plot( xlimit, c(NaN,NaN),
      ylim=c(1,ymax),
      ylab="",
      xlab="",
      type="l",
      col="#FFFFFFFF",
      main="Code Changes",
      sub=sprintf("%1d Non-Merge Commits", length(d$total)),
      yaxt="n",
      xaxt="n",
)

# TODO: dynamic tick labels
xt  <- c(  0, 10000, 20000, 30000, 40000, 50000, 60000, 70000, 80000, 90000, 100000)
xtl <- c("0", "10k", "20k", "30k", "40k" ,"50k", "60k", "70k", "80k", "90k", "100k")
# Custom y-ticks and labels, las=2 means tick labels perpendicular to axis
axis(2, at=xt, labels=xtl, las=2)

yt <- as.Date(paste(2000:2017, "-01-01", sep=''))
axis(1, at=yt,labels=c(2000:2017), las=2)

# Colors
C <- rainbow(length(unique(d$author)))

ic <- 0
for ( author in unique(d$author) ) {
    ic <- ic + 1
#    print(author)
    ii <- d$author == author
    xx <- d$date[ii]
    # Median changes per day
    median_changes <- median(diff(d$total[ii]))

    # d$total still may have wild jumps if we missed any 
    # changes that should obviously be ignored
    # ( rename directories, include javascript libraries, perltidy whole files, etc )
    # diff of d$total gives us a vector of changes per day
    # runmed(...,11) of the result applies an 11-day median filter to smooth it out
    # cumsum adds it all up, so it is a cumulative vector like the original d$total
    yy <- cumsum(runmed(diff(d$total[ii]),11))

    # handle if an author is off the chart, so we can label him
    last_on_graph <- length(yy[ yy < ymax ])
    
    # Skip anyone with fewer than 10 days of commits
    if (length(xx) > 10) {

        # xx[-1] to shorten xx by one, so it is same length as yy
        # col sets the color, pch sets the marker, cex alters the marker size
        points( xx[-1], yy, col=C[ic], pch=20, cex=0.05 )    
        if ( last_on_graph > 0 ) {

            # Do not bother labelling authors with fewer than 1000 total changes.
            if (yy[last_on_graph] > 1000) {
                # pos=4 means align left
                text( xx[last_on_graph + 1], yy[last_on_graph],
                     sprintf("%s [ %s cpd ]", author, median_changes),
                     pos=4,
                     cex=0.2,
                     col=C[ic])
            }
        }
    }
}

dev.off();
