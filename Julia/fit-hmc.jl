# fit-hmc.jl
# Fit Bayesian logistic regression using HMC in Julia

using ParquetFiles, DataFrames, Random, Distributions, Plots, StatsBase

# Define some functions

function lprior(beta)
    d = Normal(0,1)
    logpdf(Normal(0,10), beta[1]) + sum(map((bi) -> logpdf(d, bi), beta[2:8]))
end

ll(beta) = sum(-log.(1.0 .+ exp.(-(2*y .- 1.0).*(x * beta))))

lpost(beta) = lprior(beta) + ll(beta)

pscale = [10.0, 1, 1, 1, 1, 1, 1, 1]

function glp(beta)
    glpr = -beta ./ (pscale .* pscale)
    gll = transpose(x) * (y .- (1.0 ./ (1.0 .+ exp.(-x * beta))))
    glpr + gll
end

function hmcKernel(lpi, glpi, eps, l, dmm)
    d = length(dmm)
    sdmm = sqrt.(dmm)
    norm = Normal(0,1)
    function leapf(q, p)
        p = p .+ (0.5*eps).*glpi(q)
        for i in 1:l
            q = q .+ eps.*(p./dmm)
            if (i < l)
                p = p .+ eps.*glpi(q)
            else
                p = p .+ (0.5*eps).*glpi(q)
            end
        end
        vcat(q, -p)
    end
    alpi(x) = lpi(x[1:d]) - 0.5*sum((x[(d+1):(2*d)].^2)./dmm)
    rprop(x) = leapf(x[1:d], x[(d+1):(2*d)])
    mhk = mhKernel(alpi, rprop)
    function (q)
        p = rand!(rng, norm, zeros(d)).*sdmm
        mhk(vcat(q, -p))[1:d]
    end
end

function mhKernel(logPost, rprop)
    function kern(x)
        prop = rprop(x)
        a = logPost(prop) - logPost(x)
        if (log(rand(rng)) < a)
            return prop
        else
            return x
        end
    end
    kern
end

function mcmc(init, kernel, iters, thin)
    p = length(init)
    ll = -Inf
    mat = zeros(iters, p)
    x = init
    for i in 1:iters
        print(i); print(" ")
        for j in 1:thin
            x = kernel(x)
        end
        mat[i,:] = x
    end
    println(".")
    mat
end

# Main execution thread

# Load and process the data
df = DataFrame(load("../pima.parquet"))
y = df.type
y = map((yi) -> yi == "Yes" ? 1.0 : 0.0, y)
x = df[:,1:7]
x = Matrix(x)
x = hcat(ones(200, 1), x)
# Set up for doing MCMC
beta = zeros(8, 1)
beta[1] = -10
rng = MersenneTwister(1234)
norm = Normal(0, 0.02)
kern = hmcKernel(lpost, glp, 1e-3, 50, 1 ./ [100.0, 1, 1, 1, 1, 1, 25, 1])
                  
# Main MCMC loop
out = mcmc(beta, kern, 10000, 20)

# Plot results
plot(1:10000, out, layout=(4, 2))
savefig("trace-hmc.pdf")
histogram(out, layout=(4, 2))
savefig("hist-hmc.pdf")
plot(1:400, autocor(out, 1:400), layout = (4, 2))
savefig("acf-hmc.pdf")

# eof

