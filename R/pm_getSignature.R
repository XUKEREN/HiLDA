#' Obtain the parameters for mutation signatures and memberships
#' 
#' @param mutationFeatureData the mutation data (MutationFeatureData class 
#'        (S4 class)) by the \code{hildaReadMPFile}. 
#' @param K the number of mutation signatures
#' @param numInit the number of performing calculations with different initial 
#'        values
#' @param tol tolerance for the estimation
#'        (when the difference of log-likelihoods become below this value, stop 
#'        the estimation)
#' @param maxIter the maximum number of iteration of estimation
#' 
#' @return The output is an instance of EstimatedParameters S4 class, which 
#'         stores estimated parameters and other meta-information, and will be 
#'         used for saving parameter values and visualizing the mutation 
#'         signatures and memberships
#' 
#' @examples 
#' ## After obtaining G (see e.g., hildaReadMPFile function)
#' load(system.file("extdata/sample.rdata", package="HiLDA"))
#' Param <- pmgetSignature(G, K = 3)
#' 
#'
#' @useDynLib HiLDA
#' @importFrom Rcpp sourceCpp
#' @importFrom stats rgamma
#' @importFrom methods slot is
#' @export
pmgetSignature <- function(mutationFeatureData, K, numInit = 10, tol = 1e-4, 
                           maxIter = 10000) {
  
    if (is(mutationFeatureData)[1] != "MutationFeatureData") {
      stop("This inputfile is not an MutationFeatureData object.")
    }
  
    if (K <= 1) {
      stop("Please enter an integer number greater than 1.")
    }
  
    isBG <- FALSE
    varK <- K
    BG <- 0

    sampleNum <- length(slot(mutationFeatureData, "sampleList"))
    fdim <- slot(mutationFeatureData, "possibleFeatures")
  
    tempL <- -Inf
    tempPar <- c()
    for (kkk in seq_len(numInit)) {
      
      F <- array(0, c(varK, length(fdim), max(fdim)))
      
      for (k in seq_len(varK)) {
        for (kk in seq_len(length(fdim))) {
          F[k,kk,seq_len(fdim[kk])] <- stats::rgamma(fdim[kk], rep(1, fdim[kk]))
          F[k,kk,seq_len(fdim[kk])] <- 
            F[k,kk,seq_len(fdim[kk])] / sum(F[k,kk,seq_len(fdim[kk])])
        }
      }
      
  
      Q <- matrix(rgamma(sampleNum * K, 1, 1), K, sampleNum)
      Q <- sweep(Q, 2, apply(Q, 2, sum), `/`)
      
      p0 <- c(convertToTurbo_F(as.vector(F), fdim, K, isBG), 
              convertToTurbo_Q(as.vector(t(Q)), K, sampleNum))
      Y <- list(list(sampleNum, fdim, slot(mutationFeatureData, 
                                           "featureVectorList"), 
                     slot(mutationFeatureData, "countData")), K, isBG, BG)
      
      res1 <- mySquareEM(p0, Y, tol = tol, maxIter = maxIter)
      cat(paste("#trial: ", sprintf("%2d", kkk), 
                "; #iteration: ", sprintf("%4d", as.integer(res1$itr)), 
                "; time(s): ", sprintf("%4.2f", res1$elapsed.time), 
                "; convergence: ", res1$convergence,
                "; loglikelihood: ", 
                sprintf("%.4f", res1$value.objfn), "\n", sep=""
      ))
      
      if (res1$value.objfn > tempL) {
        tempL <- res1$value.objfn
        tempPar <- res1$par
      }
      
    }
    
    lenF <- varK * (sum(fdim) - length(fdim))
    lenQ <- sampleNum * (K - 1)
    F <- convertFromTurbo_F(tempPar[seq_len(lenF)], fdim, K, isBG)
    Q <- convertFromTurbo_Q(tempPar[(lenF + 1):(lenF + lenQ)], K, sampleNum)
    dim(F) <- c(varK, length(fdim), max(fdim))
    dim(Q) <- c(sampleNum, K)
    
    # return(list(F, Q, tempL))
    return(new(Class = "EstimatedParameters", 
               type = slot(mutationFeatureData, "type"),
               flankingBasesNum = slot(mutationFeatureData, "flankingBasesNum"),
               transcriptionDirection = slot(mutationFeatureData, 
                                             "transcriptionDirection"),
               possibleFeatures = slot(mutationFeatureData, "possibleFeatures"),
               sampleList = slot(mutationFeatureData, "sampleList"),
               signatureNum = as.integer(K),
               isBackGround = isBG,
               backGroundProb = BG,
               signatureFeatureDistribution = F,
               sampleSignatureDistribution = Q,
               loglikelihood = tempL)
    )
 
}




#' A function for estimating parameters using Squared EM algorithm
#' 
#' @param p this variable includes the parameters for mutation signatures and 
#'          membership parameters
#' @param y this variable includes the information on the mutation features, 
#' the number of mutation signatures specified and so on
#' @param tol tolerance for the estimation
#'            (when the difference of log-likelihoods become below this value, 
#'            stop the estimation)
#' @param maxIter the maximum number of iteration of estimation
#' @return a list 
mySquareEM <- function(p, y, tol = 1e-4, maxIter = 10000) {
  
    prevL <- -Inf
    step.min <- 1
    step.max <- 1
    step.max0 <- 1
    mstep <- 4
    objfn.inc <- 1
    updEvalNum <- 0
    LEvalNum <- 0
    useSquareEM <- 0
    iterNum <- 0
    convFlag <- FALSE
    startTime <- proc.time()
    
    newL <- calcPMSLikelihood(p, y)
    LEvalNum <- LEvalNum + 1
    
    for (iterNum in seq_len(maxIter)) {
      
      p1 <- updatePMSParam(p, y)
      updEvalNum <- updEvalNum + 1
      if ( any(is.nan(unlist(p1))) ) {
        stop("Error in function evaluation")
      }
      
      q1 <- p1 - p
      sr2 <- crossprod(q1)
      
      p2 <- updatePMSParam(p1, y)
      updEvalNum <- updEvalNum + 1
      if ( any(is.nan(unlist(p2))) ) {
        stop("Error in function evaluation")
      }
      
      q2 <- p2 - p1
      sq2 <- sqrt(crossprod(q2))
      sv2 <- crossprod(q2 - q1)
      srv <- crossprod(q1, q2 - q1)
      
      # alpha <- switch(ctrl$version, -srv/sv2, -sr2/srv, sqrt(sr2/sv2))
      alpha <- -srv/sv2
      alpha <- max(step.min, min(step.max, alpha))
      p.new <- p + 2 * alpha * q1 + alpha^2 * (q2 - q1)
      
      # This step is done in the original turboEM code...
      # but I cannot understand why this step is necessary....
      if (isTRUE(abs(alpha - 1) > 0.01) ) {
        p.new <- updatePMSParam(p.new, y)
        updEvalNum <- updEvalNum + 1
      }
      
      # when p.new has some problems...
      if (any(is.nan(p.new)) | !PMSboundary(y)(p.new) ) {
        
        p.new <- p2
        newL <- calcPMSLikelihood(p2, y)
        LEvalNum  <- LEvalNum + 1
        
        # since there was a problem, consider to reduce the amount of step max
        if (isTRUE(all.equal(alpha, step.max))) {
          step.max <- max(step.max0, step.max / mstep)
        }
        alpha <- 1
        
        # when p.new is O.K....
      } else {
        
        newL <- calcPMSLikelihood(p.new, y)
        LEvalNum  <- LEvalNum + 1
        
        # when the calculated log-likelihood has some problems
        # or the difference betwen the calculated log-likelihood is large...
        if (is.nan(newL) | (newL > prevL + objfn.inc)) {
          
          p.new <- p2
          lnew <- calcPMSLikelihood(p2, y)
          LEvalNum  <- LEvalNum + 1
          
          # since there was a problem, consider to reduce the amount of step max
          if (alpha == step.max) {
            step.max <- max(step.max0, step.max / mstep)
          }
          alpha <- 1
          
        } else {
          useSquareEM <- useSquareEM + 1
        }
        
      }
      
      if (isTRUE(all.equal(alpha, step.max))) {
        step.max <- mstep * step.max
      }
      
      if (step.min < 0 & isTRUE(all.equal(alpha, step.min))) {
        step.min <- mstep * step.min
      }
      
      p <- p.new
      
      # for debugging
      # print(c(updEvalNum, LEvalNum, useSquareEM, step.min, step.max, newL))
      
      if (abs(prevL - newL) < tol) {
        convFlag <- TRUE
        break
      }
      
      if (!is.nan(newL)) {
        prevL <- newL
      }
      
    }
    
    calcTime <- proc.time() - startTime
    
    return(list(par = p,
                value.objfn = newL,
                itr = iterNum,
                fpeval = updEvalNum,
                convergence = convFlag,
                elapsed.time = calcTime[3]))
    
}



#' A function for updating parameters using EM-algorithm
#' 
#' @param p this variable includes the parameters for mutation signatures and 
#'          membership parameters
#' @param y this variable includes the information on the mutation features, 
#'          the number of mutation signatures specified and so on
#' @return a value
updatePMSParam <- function(p, y) {
  
    sampleNum <- y[[1]][[1]]
    fdim <- y[[1]][[2]]
    patternList <- y[[1]][[3]]
    sparseCount <- y[[1]][[4]]
    K <- y[[2]]
    isBG <- y[[3]]
    BG0 <- y[[4]]
    
    patternNum <- ncol(patternList)
    samplePatternNum <- ncol(sparseCount)
  
    
    if (isBG) {
      varK <- K - 1
    } else {
      varK <- K
    }
    
    lenF <- varK * (sum(fdim) - length(fdim))
    lenQ <- (K - 1) * sampleNum
    F <- convertFromTurbo_F(p[seq_len(lenF)], fdim, K, isBG)
    Q <- convertFromTurbo_Q(p[(lenF + 1):(lenF + lenQ)], K, sampleNum)
    
    dim(Q) <- c(sampleNum, K)
    Q <- t(Q)
    ####################
    # E-step
    Theta <- updateTheta_NormalizedC(as.vector(patternList), 
                                     as.vector(sparseCount), as.vector(F), 
                                     as.vector(Q), fdim, K, sampleNum, 
                                     patternNum, samplePatternNum, isBG, BG0)
  
    dim(Theta) <- c(K, samplePatternNum)
    
    ####################
    # M-step 
    F_Q <- updateMstepFQC(as.vector(patternList), as.vector(sparseCount), 
                          as.vector(Theta), fdim, K, sampleNum, 
                          patternNum, samplePatternNum, isBG)
    #########################################
    F <- F_Q[seq_len((varK * length(fdim) * max(fdim)))]
    Q <- F_Q[(varK * length(fdim) * max(fdim) + 1):
               (varK * length(fdim) * max(fdim) + K * sampleNum)]
    dim(F) <- c(varK, length(fdim), max(fdim))
    dim(Q) <- c(K, sampleNum)
    Q <- t(Q)
    
    return(c(convertToTurbo_F(as.vector(F), fdim, K, isBG),  
             convertToTurbo_Q(as.vector(Q), K, sampleNum)))
    
}


#' A function for calculating the log-likelihood from the data and parameters
#' 
#' @param p this variable includes the parameters for mutation signatures and 
#'          membership parameters
#' @param y this variable includes the information on the mutation features, 
#'          the number of mutation signatures specified and so on
#' @return a value
calcPMSLikelihood <- function(p, y) {
  
    sampleNum <- y[[1]][[1]]
    fdim <- y[[1]][[2]]
    patternList <- y[[1]][[3]]
    sparseCount <- y[[1]][[4]]
    K <- y[[2]]
    isBG <- y[[3]]
    BG0 <- y[[4]]
    
    patternNum <- ncol(patternList)
    samplePatternNum <- ncol(sparseCount)
    
    
    if (isBG) {
      varK <- K - 1
    } else {
      varK <- K
    }
    
    lenF <- varK * (sum(fdim) - length(fdim))
    lenQ <- (K - 1) * sampleNum
    F <- convertFromTurbo_F(p[seq_len(lenF)], fdim, K, isBG)
    Q <- convertFromTurbo_Q(p[(lenF + 1):(lenF + lenQ)], K, sampleNum)
    
    dim(Q) <- c(sampleNum, K)
    Q <- t(Q)
    ####################
    
    return(getLogLikelihoodC(as.vector(patternList), as.vector(sparseCount), 
                             as.vector(F), as.vector(Q), fdim, K, 
                             sampleNum, patternNum, samplePatternNum, 
                             isBG, BG0))

}


#' A functional for generating the function checking the parameter (p) is 
#' within the restricted conditions or not
#' 
#' @param y this variable includes the information on the mutation features, 
#' the number of mutation signatures specified and so on
#' @return a functional
PMSboundary <- function(y) {
  
    sampleNum <- y[[1]][[1]]
    fdim <- y[[1]][[2]]
    patternList <- y[[1]][[3]]
    sparseCount <- y[[1]][[4]]
    K <- y[[2]]
    isBG <- y[[3]]
    F0 <- y[[4]]
    
    patternNum <- ncol(patternList)
    samplePatternNum <- ncol(sparseCount)
    
    
    if (isBG) {
      varK <- K - 1
    } else {
      varK <- K
    }
    
    lenF <- varK * (sum(fdim) - length(fdim))
    lenQ <- (K - 1) * sampleNum
  
    
    function(p) {
      return(all(boundaryTurbo_F(p[seq_len(lenF)], fdim, varK), 
                 boundaryTurbo_Q(p[(lenF + 1):(lenF + lenQ)], K, sampleNum)))
    }
    
}
