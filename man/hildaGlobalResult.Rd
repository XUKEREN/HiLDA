% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/hilda_diagnosis.R
\name{hildaGlobalResult}
\alias{hildaGlobalResult}
\title{Compute the Bayes factor}
\usage{
hildaGlobalResult(jagsOutput, pM1 = 0.5)
}
\arguments{
\item{jagsOutput}{the output jags file generated by the jags function from
the R2jags package.}

\item{pM1}{the probability of sampling the null (default: 0.5)}
}
\value{
a number for the Bayes factor
}
\description{
Compute the Bayes factor
}
\examples{

load(system.file("extdata/sample.rdata", package="HiLDA"))
hildaGlobal <- hildaTest(inputG=G, numSig=3, refGroup=1:4, nIter=1000,
localTest=TRUE)
hildaGlobalResult(hildaGlobal)

}
