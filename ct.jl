using Distributed

# @everywhere 
using Distributions, Interpolations, Optim, HCubature, QuantEcon, LaTeXStrings, Printf, PlotlyJS, Distributed, SharedArrays, Dates, JLD

# @everywhere 
include("type_def.jl")
# @everywhere 
include("reporting_routines.jl")
# @everywhere 
include("simul.jl")
# @everywhere 
include("plotting_routines.jl")

function output_bayes(ct::CrazyType, pv, av)
	knots = (ct.pgrid, ct.agrid);
	itp_gπ = interpolate(knots, ct.gπ, Gridded(Linear()));

	# exp_π = pv*av + (1-pv)*itp_gπ(pv, av)
	exp_π = itp_gπ(pv, av)

	println("gπ = [$(annualized(itp_gπ(pv, av))-1.96*ct.σ), $(annualized(itp_gπ(pv, av))+1.96*ct.σ)], av = $(annualized(av))")

	println("$(pdf_ϵ(ct, exp_π - av ))")
	println("$(pdf_ϵ(ct, 0.0 ))")

	aprime = ϕ(ct, av)
	π_myopic = pv * aprime + (1.0-pv) * itp_gπ(pv, aprime)

	Nv = 50
	yv = zeros(Nv)
	ym = zeros(Nv)
	πvec = range(av - 1.96*ct.σ, av + 1.96*ct.σ, length=Nv)
	for (jj, πv) in enumerate(πvec)

		pprime = Bayes(ct, πv, exp_π, pv, av)
		exp_π′ = pprime * aprime + (1.0-pprime) * itp_gπ(pprime, aprime)
		yv[jj] = PC(ct, πv, exp_π, exp_π′)
		ym[jj] = PC(ct, πv, exp_π, π_myopic)

		# yv[jj] = pdf_ϵ(ct, πv - av)
		# yv[jj] = pprime

	end

	plot([
		scatter(;x=annualized.(πvec), y=yv)
		# scatter(;x=annualized.(πvec), y=ym)
		])
end

function Bayes(ct::CrazyType, obs_π, exp_π, pv, av)

	numer = pv * pdf_ϵ(ct, obs_π - av)
	denomin = numer + (1.0-pv) * pdf_ϵ(ct, obs_π - exp_π)

	p′ = numer / denomin

	p′ = max(0.0, min(1.0, p′))

	if isapprox(denomin, 0.0)
		p′ = 0.0
	end
	# drift = (1.0 - pv) * 0.15
	# drift = -(pv) * 0.15

	return p′
end

PC(ct::CrazyType{Forward}, obs_π, πe, exp_π′) = (1/ct.κ) * (obs_π - ct.β * exp_π′)
PC(ct::CrazyType{Simultaneous}, obs_π, πe, exp_π′) = 1/ct.κ  * (obs_π - πe)

function cond_Ldev(ct::CrazyType, itp_gπ, itp_L, obs_π, pv, av)
	aprime = ϕ(ct, av)

	πe = pv*av + (1-pv)*exp_π
	exp_π′ = itp_gπ(0.0, aprime)

	y = PC(ct, obs_π, πe, exp_π′) # Automatically uses method for forward or backward
	L′ = itp_L(0.0, aprime)

	L = (ct.ystar-y)^2 + ct.γ * obs_π^2 + ct.β * L′

	return L
end

function cond_L(ct::CrazyType, itp_gπ, itp_L, itp_C, obs_π, pv, av; get_y::Bool=false)
	exp_π  = itp_gπ(pv, av)
	if isapprox(pv, 0.0)
		pprime = 0.0
	elseif isapprox(pv, 1.0)
		pprime = 1.0
	else
		pprime = Bayes(ct, obs_π, exp_π, pv, av)
	end
	aprime = ϕ(ct, av)

	πe = pv*av + (1-pv)*exp_π

	L′ = itp_L(pprime, aprime)
	C′ = itp_C(pprime, aprime)
	exp_π′ = pprime * aprime + (1.0-pprime) * itp_gπ(pprime, aprime)

	y = PC(ct, obs_π, πe, exp_π′) # Automatically uses method for forward or backward
	L = (ct.ystar-y)^2 + ct.γ * obs_π^2 + ct.β * L′
	if get_y
		return y, pprime, C′
	end
	return L
end

function exp_L(ct::CrazyType, itp_gπ, itp_L, itp_C, control_π, pv, av; get_y::Bool=false)

	f(ϵv) = cond_L(ct, itp_gπ, itp_L, itp_C, control_π + ϵv, pv, av) * pdf_ϵ(ct, ϵv)
	(val, err) = hquadrature(f, -3.09*ct.σ, 3.09*ct.σ, rtol=1e-10, atol=0, maxevals=0)

	# sum_prob, err = hquadrature(x -> pdf_ϵ(ct, x), -3.09*ct.σ, 3.09*ct.σ, rtol=1e-10, atol=0, maxevals=0)
	sum_prob = cdf_ϵ(ct, 3.09*ct.σ) - cdf_ϵ(ct, -3.09*ct.σ)

	val = val / sum_prob

	if get_y
		f_y(ϵv) = cond_L(ct, itp_gπ, itp_L, itp_C, control_π + ϵv, pv, av; get_y=true)[1] * pdf_ϵ(ct, ϵv)
		Ey, err = hquadrature(f_y, -3.09*ct.σ, 3.09*ct.σ, rtol=1e-10, atol=0, maxevals=0)
		f_p(ϵv) = cond_L(ct, itp_gπ, itp_L, itp_C, control_π + ϵv, pv, av; get_y=true)[2] * pdf_ϵ(ct, ϵv)
		Ep, err = hquadrature(f_p, -3.09*ct.σ, 3.09*ct.σ, rtol=1e-10, atol=0, maxevals=0)
		f_C(ϵv) = cond_L(ct, itp_gπ, itp_L, itp_C, control_π + ϵv, pv, av; get_y=true)[3] * pdf_ϵ(ct, ϵv)
		Ec, err = hquadrature(f_p, -3.09*ct.σ, 3.09*ct.σ, rtol=1e-10, atol=0, maxevals=0)

		Ey = Ey / sum_prob
		Ep = Ep / sum_prob
		Ec = Ec / sum_prob

		return Ey, Ep, Ec
	end

	return val
end

function opt_L(ct::CrazyType, itp_gπ, itp_L, itp_C, π_guess, pv, av)

	minπ = max(0, π_guess - 3.09*ct.σ)
	maxπ = min(1.1*maximum(ct.agrid), π_guess + 3.09*ct.σ)
	if maxπ < minπ + 1.1*maximum(ct.agrid) / 10
		maxπ = minπ + 1.1*maximum(ct.agrid) / 10
	end
	
#=	res = Optim.optimize(
			gπ -> exp_L(ct, itp_gπ, itp_L, itp_C, gπ, pv, av),
			minπ, maxπ, GoldenSection()#, rel_tol=1e-20, abs_tol=1e-20, iterations=10000
			)
=#
	
	obj_f(x) = exp_L(ct, itp_gπ, itp_L, itp_C, x, pv, av)
	res = Optim.optimize(
		gπ -> obj_f(first(gπ)),
		[π_guess], LBFGS()#, autodiff=:forward#, Optim.Options(f_tol=1e-12)
		)

	gπ, L = first(res.minimizer), res.minimum

	if Optim.converged(res) == false
		# a = Optim.iterations(res)
		# print_save("π∈ [$minπ, $maxπ]")
		# println(a)
		resb = Optim.optimize(
				gπ -> exp_L(ct, itp_gπ, itp_L, itp_C, gπ, pv, av),
				minπ, maxπ, Brent(), rel_tol=1e-12, abs_tol=1e-12#, iterations=100000
				)
		if resb.minimum < res.minimum
			gπ, L = resb.minimizer, resb.minimum
		end
	end

	return gπ, L
end

function optim_step(ct::CrazyType, itp_gπ, itp_L, itp_C, gπ_guess; optimize::Bool=true)
	# gπ, L  = SharedArray{Float64}(ct.gπ), SharedArray{Float64}(ct.L)
	# Ey, Eπ = SharedArray{Float64}(ct.Ey), SharedArray{Float64}(ct.Eπ)
	# Ep, C  = SharedArray{Float64}(ct.Ep), SharedArray{Float64}(ct.C)
	gπ, L  = zeros(size(ct.gπ)), zeros(size(ct.L))
	Ey, Eπ = zeros(size(ct.Ey)), zeros(size(ct.Eπ))
	Ep, C  = zeros(size(ct.Ep)), zeros(size(ct.C))
	πN 	   = Nash(ct)
	apgrid = gridmake(1:ct.Np, 1:ct.Na)
	Threads.@threads for js in 1:size(apgrid,1)
	# @sync @distributed  for js in 1:size(apgrid,1)
    # for js in 1:size(apgrid,1)
		jp, ja = apgrid[js, :]
		pv, av = ct.pgrid[jp], ct.agrid[ja]
		π_guess = gπ_guess[jp, ja]
		if optimize
			# π_guess = itp_gπ(pv, av)
			gπ[jp, ja], L[jp, ja] = opt_L(ct, itp_gπ, itp_L, itp_C, π_guess, pv, av)
		else
			gπ[jp, ja] = π_guess
			L[jp, ja] = exp_L(ct, itp_gπ, itp_L, itp_C, π_guess, pv, av)
		end
		Ey[jp, ja], Ep[jp, ja], EC′ = exp_L(ct, itp_gπ, itp_L, itp_C, π_guess, pv, av; get_y=true)
		Eπ[jp, ja] = pv * av + (1.0 - pv) * gπ[jp, ja]

		if av >= πN || isapprox(av, πN)
			C[jp, ja] = (1-ct.β)*1 + ct.β * EC′
		else
			C[jp, ja] = (1-ct.β)*(πN - Eπ[jp,ja])/(πN-av) + ct.β * EC′
		end
	end

	return gπ, L, Ey, Eπ, Ep, C
end

function pf_iter(ct::CrazyType, Egπ, gπ_guess; optimize::Bool=true)
	#=	
	knots = (ct.pgrid[2:end], ct.agrid)
	itp_gπ_1 = interpolate(knots, Egπ[2:end,:],  Gridded(Linear()))
	itp_gπ_2 = extrapolate(itp_gπ_1, Flat())
	itp_L_1 = interpolate(knots, ct.L[2:end,:],  Gridded(Linear()))
	itp_L_2 = extrapolate(itp_L_1, Flat())

	η = 0.9
	plow = ct.pgrid[2] * η + ct.pgrid[1] * (1-η)
	gπ_lowp = [itp_gπ_2(plow, av) for (ja, av) in enumerate(ct.agrid)]
	L_lowp = [itp_L_2(plow, av) for (ja, av) in enumerate(ct.agrid)]

	pgrid_large = [ct.pgrid[1]; plow; ct.pgrid[2:end]]

	gπ_large = Array{Float64}(undef, ct.Np+1, ct.Na)
	L_large = Array{Float64}(undef, ct.Np+1, ct.Na)
	for jp in 1:ct.Np+1
		for (ja, av) in enumerate(ct.agrid)
			if jp > 2
				gπ_large[jp, ja] = Egπ[jp-1,ja]
				L_large[jp, ja] = ct.L[jp-1,ja]
			elseif jp == 1
				gπ_large[jp, ja] = gπ_lowp[ja]
				L_large[jp, ja] = L_lowp[ja]
			else
				gπ_large[jp, ja] = Egπ[1, ja]
				L_large[jp, ja] = ct.L[1, ja]
			end
		end
	end
	knots = (pgrid_large, ct.agrid)
	itp_gπ = interpolate(knots, gπ_large, Gridded(Linear()))
	itp_L  = interpolate(knots, L_large, Gridded(Linear()))
	=#
	knots = (ct.pgrid, ct.agrid)
	itp_gπ = interpolate(knots, Egπ, Gridded(Linear()))
	itp_L  = interpolate(knots, ct.L, Gridded(Linear()))
	itp_C  = interpolate(knots, ct.C, Gridded(Linear()))


	new_gπ, new_L, new_y, new_π, new_p, new_C = optim_step(ct, itp_gπ, itp_L, itp_C, gπ_guess; optimize=optimize)

	return new_gπ, new_L, new_y, new_π, new_p, new_C
end

function pfi!(ct::CrazyType, Egπ; tol::Float64=1e-12, maxiter::Int64=1000, verbose::Bool=true, reset_guess::Bool=false)
	dist = 10.
	iter = 0
	upd_η2 = 0.75

	rep = "\nStarting PFI (tol = $(@sprintf("%0.3g",tol)))"
	verbose ? print_save(rep,true) : print(rep)

    if reset_guess
	    ct.gπ = zeros(size(ct.gπ))
		ct.L = ones(ct.Np, ct.Na)
	end

	old_gπ = copy(Egπ)
	new_gπ = zeros(size(old_gπ))

	while dist > tol && iter < maxiter
		iter += 1

		for jj in 1:10
			_, new_L, _, _, _ = pf_iter(ct, Egπ, old_gπ; optimize=false)
			ct.L  = upd_η2 * new_L  + (1.0-upd_η2) * ct.L
		end

		old_L = copy(ct.L)

		new_gπ, new_L, new_y, new_π, new_p, new_C = pf_iter(ct, Egπ, old_gπ)

		dist = sqrt.(sum( (new_L  - old_L ).^2 )) / sqrt.(sum(old_L .^2))

		ct.L  = upd_η2 * new_L  + (1.0-upd_η2) * ct.L
		old_gπ = upd_η2 * new_gπ + (1.0-upd_η2) * old_gπ
		ct.Ey = new_y
		ct.Eπ = new_π
		ct.Ep = new_p
		ct.C  = new_C

		# if verbose && iter % 10 == 0
		# 	print("\nAfter $iter iterations, d(L) = $(@sprintf("%0.3g",dist))")
		# end
	end

	dist2 = 10.
	iter2 = 0
	while dist > tol && iter2 < maxiter
		iter2 += 1
		old_C = copy(ct.C)
		_, _, _, _, _, new_C = pf_iter(ct, Egπ, old_gπ; optimize=false)
		dist2 = sqrt.(sum( (new_C  - old_C ).^2 )) / sqrt.(sum(old_C .^2))
		ct.C  = upd_η2 * new_C  + (1.0-upd_η2) * ct.C
	end

	if verbose && dist <= tol
		print("\nConverged in $iter iterations.")
	elseif verbose
		print("\nAfter $iter iterations, d(L) = $(@sprintf("%0.3g",dist))")
	end

	return (dist <= tol), new_gπ
end

decay_η(ct::CrazyType, η) = max(0.95*η, 5e-6)

function Epfi!(ct::CrazyType; tol::Float64=5e-4, maxiter::Int64=2500, verbose::Bool=true, tempplots::Bool=false, upd_η::Float64=0.01, switch_η = 10)
	dist = 10.
	iter = 0
	
	print_save("\nRun with ω = $(@sprintf("%.3g",ct.ω)), χ = $(@sprintf("%.3g",annualized(ct.χ)))% at $(Dates.format(now(), "HH:MM"))")

	dists = []

	reset_guess = false
	tol_pfi = 1e-3 / 0.99
	while dist > tol && iter < maxiter
		iter += 1
		tol_pfi = max(tol_pfi*0.98, 2e-6)

		old_gπ, old_L = copy(ct.gπ), copy(ct.L);

		flag, new_gπ = pfi!(ct, old_gπ; verbose=verbose, reset_guess=reset_guess, tol=tol_pfi);
		reset_guess = !flag

		dist = sqrt.(sum( (new_gπ  - ct.gπ ).^2 )) / sqrt.(sum(ct.gπ .^2))
		push!(dists, dist)
		rep_status = "\nAfter $iter iterations, d(π) = $(@sprintf("%0.3g",dist))"
		if flag
			rep_status *= "✓ "
		end
		if verbose #&& iter % 10 == 0
			print_save(rep_status*"\n", true)
		else
			print(rep_status)
		end

		ct.gπ = upd_η * new_gπ + (1.0-upd_η) * ct.gπ;

		if tempplots && (iter % 5 == 0 || dist <= tol)
			p1, pL, pE, pC, pp = makeplots_ct_pa(ct);
			relayout!(p1, title="iter = $iter")
			savejson(p1, pwd()*"/../Graphs/tests/temp.json")
			relayout!(pL, title="iter = $iter")
			savejson(pL, pwd()*"/../Graphs/tests/tempL.json")
			# relayout!(pE, title="iter = $iter")
			# savejson(pE, pwd()*"/../Graphs/tests/tempLpE.json")
			p2 = makeplot_conv(dists; switch_η=switch_η);
			savejson(p2, pwd()*"/../Graphs/tests/tempconv.json")
		end

		if iter == floor(Int, switch_η*0.4)
			upd_η = min(upd_η, 0.01)
		elseif iter % switch_η == 0
			upd_η = decay_η(ct, upd_η) # Automatically uses the updating method for fwd or bwd
		end
		if verbose
			print_save("new upd_η = $(@sprintf("%0.3g", upd_η))", true)
		end

	end
	if verbose && dist <= tol
		print_save("\nConverged in $iter iterations.",true)
	elseif verbose
		print_save("\nAfter $iter iterations, d(L) = $(@sprintf("%0.3g",dist))",true)
	end
	p1, pL, pπ, pC, pp = makeplots_ct_pa(ct);
	savejson(pC, pwd()*"/../Graphs/tests/tempC.json")
	savejson(pπ, pwd()*"/../Graphs/tests/tempg.json")
	
	return dist
end

# function choose_ω!(L_mat, ct::CrazyType{Forward}, Nω=size(L_mat,1); remote::Bool=true, upd_η=0.1)
# 	choose_ω!(L_mat, ct, Forward, Nω; remote=remote, upd_η=upd_η)
# end

# function choose_ω!(L_mat, ct::CrazyType{Simultaneous}, Nω=size(L_mat,1); remote::Bool=true, upd_η=0.1)
# 	choose_ω!(L_mat, ct, Simultaneous, Nω; remote=remote, upd_η=upd_η)
# end

function choose_ω!(L_mat, ct::CrazyType, Nω=size(L_mat,1); upd_η=0.1)
	T = which_PC(ct)
	ct_best = CrazyType(T; γ=ct.γ, κ=ct.κ, σ=ct.σ, β=ct.β, ystar=ct.ystar)

	if T == Simultaneous
		ωmax = 3.0
	elseif T == Forward
		ωmax = 1.25
	end
	ωgrid = cdf.(Beta(1,1), range(1,0,length=Nω))
	move_grids!(ωgrid, xmax = ωmax, xmin = 0.01)

	Na = length(ct.agrid)
	Nχ = size(L_mat, 2)
	χgrid = range(0.0, 0.5*Nash(ct), length = Nχ)

	print_save("\nLooping over behavioral types with ω ∈ [$(minimum(ωgrid)), $(maximum(ωgrid))]")
	print_save("\n")

	L_min = 100.
	ω_min = 1.0
	χ_min = 1.0
	a_min = 1.0
	t0 = time()
	Lplot = []
	aplot = []
	C_mat = zeros(Na, Nω, Nχ) * NaN
	L_mat_ctour = zeros(Nω, Nχ) * NaN
	C_mat_ctour = zeros(Nω, Nχ) * NaN
	Lmin = 1e8
	ja_min = 1
	for (jχ, χv) in enumerate(χgrid)
		L_vec = []
		a_vec = []
		ω_vec = []

		""" tol = 11e-4 """
		function wrap_Epfi!(ct::CrazyType, ωv, L_vec, a_vec, ω_vec, Lplot, L_mat_save, C_mat, aplot, jω, jχ)
			ct.ω = ωv

			t1 = time()
			tol = 10e-4 # 11!!!!
			# if length(L_vec) > 0
			# 	upd_η = 0.005
			# end
			dist = Epfi!(ct, verbose = true, tol=tol, tempplots=false, upd_η=upd_η)
			write(pwd()*"/../temp.txt", "")
			
			flag = (dist <= tol)
			Lmin, ja = findmin(ct.L[3,:])
			Cmin = ct.C[3,ja]
			# Cmin = ct.C[3,end]

			C_mat[:,jω,jχ] = ct.C[3,:]
			
			s = ": done in $(time_print(time()-t1))"
			flag ? s = s*" ✓" : nothing
			print_save(s)

			L_mat_save[:,:] = ct.L

			push!(L_vec, Lmin)
			push!(a_vec, ct.agrid[ja])
			push!(ω_vec, ωv)

			perm_order = sortperm(ω_vec)

			new_L = scatter(;x=ω_vec[perm_order], y=L_vec[perm_order], name = "χ = $(@sprintf("%.3g",annualized(χv)))%", line_shape="spline")
			new_a = scatter(;x=ω_vec[perm_order], y=annualized.(a_vec[perm_order]), name = "χ = $(@sprintf("%.3g",annualized(χv)))%")

			all_Ls = new_L
			all_as = new_a
			if length(Lplot) == 0
			else
				all_Ls = vcat([Lplot[jj] for jj in 1:length(Lplot)], new_L)
				all_as = vcat([aplot[jj] for jj in 1:length(aplot)], new_a)
			end
			p3 = plot(all_Ls)
			relayout!(p3, title="lim_𝑝 min_𝑎 𝓛(𝑝,𝑎,ω,χ)", xaxis=attr(;zeroline=false, title="ω"))
			savejson(p3, pwd()*"/../Graphs/tests/Loss_omega.json")
	
			p4 = plot(all_as)
			relayout!(p4, title="lim_𝑝 arg min_𝑎 𝓛(𝑝,𝑎,ω,χ)", xaxis=attr(;zeroline=false, title="ω"), yaxis_title="%", mode="lines+markers")
			savejson(p4, pwd()*"/../Graphs/tests/a0.json")

			return Lmin, Cmin, ja, flag
		end

		ωmin = 1e8
		amin = 1e8
		for (jω, ωv) in enumerate(ωgrid)
			ωv = ωgrid[jω]
			old_L, old_gπ = copy(ct.L), copy(ct.gπ)
			if jω == 1 && jχ > 1
				old_ct = load("../ct_1_temp.jld", "ct")
				old_L, old_gπ = copy(old_ct.L), copy(old_ct.gπ)
			end

			ct = CrazyType(T; χ = χv, γ=ct.γ, κ=ct.κ, σ=ct.σ, β=ct.β, ystar=ct.ystar)
			
			ct.L, ct.gπ = old_L, old_gπ
			
			L_mat_save = zeros(ct.Np, ct.Na)
			L, C, ja, flag = wrap_Epfi!(ct, ωv, L_vec, a_vec, ω_vec, Lplot, L_mat_save, C_mat, aplot, jω, jχ)

			L_mat[jω, jχ, :, :] = L_mat_save
			L_mat_ctour[jω, jχ] = L

			C_mat_ctour[jω, jχ] = C 

			pLct = plot_L_contour(ωgrid, χgrid, L_mat_ctour, name_y="𝓛")
			savejson(pLct, pwd()*"/../Graphs/tests/contour.json")

			# pCct = plot_L_contour(ωgrid, χgrid, C_mat_ctour)
			# savejson(pCct, pwd()*"/../Graphs/tests/Ccontour.json")			

			# print_save("\nCurrent L = $L against current min = $Lmin")

			if jω == 1
				save("../../ct_1_temp.jld", "ct", ct)
				save("../ct_1_temp.jld", "ct", ct)
			end


			if jχ == 1 && jω == 2 && flag
				save("../../ct_1.jld", "ct", ct)
				save("../ct_1.jld", "ct", ct)
			end

			if L < L_min
				L_min = L_mat_ctour[jω, jχ]
				ω_min = ωv
				χ_min = χv
				a_min = a_vec[jω]
				ja_min = ja

				save("../../ct_opt.jld", "ct", ct)
				ct_best.ω, ct_best.χ = ωv, χv
				ct_best.L, ct_best.gπ = ct.L, ct.gπ

				_, pL, pπ, _, pp = makeplots_ct_pa(ct);
				savejson(pL, pwd()*"/../Graphs/tests/opt_L.json")
				savejson(pπ, pwd()*"/../Graphs/tests/opt_g.json")
				savejson(pp, pwd()*"/../Graphs/tests/opt_p.json")


				psim, pLsim = plot_simul(ct, T = 40, N = 50000, jp0 = 3)
				savejson(psim, pwd()*"/../Graphs/tests/simul_opt.json")
				savejson(pLsim,pwd()*"/../Graphs/tests/simul_Lopt.json")
			end
			if jω == length(ωgrid) && jχ == 1
				psim, pLsim = plot_simul(ct, T = 40, N = 50000, jp0 = 3)
				savejson(psim, pwd()*"/../Graphs/tests/simul_1.json")
				savejson(pLsim,pwd()*"/../Graphs/tests/simul_L1.json")
				_, pL, pπ, _, pp = makeplots_ct_pa(ct);
				savejson(pL, pwd()*"/../Graphs/tests/first_L.json")
				savejson(pπ, pwd()*"/../Graphs/tests/first_g.json")
				savejson(pp, pwd()*"/../Graphs/tests/first_p.json")
			end

			pCct = plot_L_contour(ωgrid, χgrid, C_mat[ja_min,:,:], name_y="C")
			savejson(pCct, pwd()*"/../Graphs/tests/Ccontour.json")			

		end

		s = "\nMinimum element is $(@sprintf("%.3g",Lmin)) with a₀ = $(@sprintf("%.3g", annualized(amin)))"
		# Optim.converged(res) ? s = s*" ✓" : nothing
		print_save(s)

		perm_order = sortperm(ω_vec)

		ω_vec = ω_vec[perm_order]
		L_vec = L_vec[perm_order]
		a_vec = a_vec[perm_order]

		new_L = scatter(;x=ω_vec, y=L_vec, name = "χ = $(@sprintf("%.3g",annualized(χv)))%")
		push!(Lplot, new_L)

		new_a = scatter(;x=ω_vec, y=annualized.(a_vec), name = "χ = $(@sprintf("%.3g",annualized(χv)))%")
		push!(aplot, new_a)

		#=
			if remote
				p1 = makeplots_ct_pa(ct)
				relayout!(p1, title="ω = $(@sprintf("%.3g",ct.ω))", width=1200, height=900)
				savejson(p1, pwd()*"/../Graphs/tests/summary_jom_$(jω).json")

				p2 = plot_simul(ct);
				savejson(p2, pwd()*"/../Graphs/tests/simul_jom_$(jω).json");
			end
		=#
	end

	print_save("\nWent through the spectrum of ω's in $(time_print(time()-t0))")
	print_save("\nOverall minimum announcement c = (a₀, ω, χ) = $(annualized(a_min)), $ω_min, $(annualized(χ_min))")

	p1 = plot_plans_p(ct, L_mat, ωgrid, χgrid)
	savejson(p1, pwd()*"/../Graphs/tests/plans.json")

	ν = ones(length(ωgrid), length(χgrid), length(ct_best.agrid))
	ν *= 1/sum(ν)
	mt = MultiType(ct_best, ωgrid, χgrid, 0.1, ν, ν, L_mat)

	return annualized(a_min), ω_min, annualized(χ_min), mt
end

Bayes_plan(ν, z, μ) = z*ν / (z*ν + (1-z)*μ)

function eval_k_to_mu(mt::MultiType, k, itp_L; get_mu::Bool=false)

	ωgrid, χgrid, L_mat = mt.ωgrid, mt.χgrid, mt.L_mat
	pgrid, agrid = mt.ct.pgrid, mt.ct.agrid

	μ, p0 = [zeros(length(ωgrid), length(χgrid), length(agrid)) for jj in 1:2]

	for (ja, av) in enumerate(agrid), (jχ, χv) in enumerate(χgrid), (jω, ωv) in enumerate(ωgrid)
		if L_mat[jω, jχ, end, ja] > k
			pv = 0.0
			μ[jω, jχ, ja] = 0.0
		else
			res = Optim.optimize(
				p -> (itp_L(ωv, χv, p, av) - k)^2, 0, 1, GoldenSection())

			disp = sqrt(res.minimum)
			if disp > 1e-4
				print_save("WARNING: Couldn't find p0 at state ($ωv, $χv, $av)")
			end
			pv = res.minimizer

			νv = mt.ν[jω, jχ, ja]
			res = Optim.optimize(
				μ -> (Bayes_plan(νv, mt.z, μ) - pv)^2, 0, 1, GoldenSection())
			disp = res.minimum
			if disp > 1e-4
				print_save("WARNING: Couldn't find p0 at state ($ωv, $χv, $av)")
			end
			μv = res.minimizer

			μ[jω, jχ, ja] = μv
		end
		p0[jω, jχ, ja] = pv
	end
	if get_mu 
		return μ
	else
		return sum(μ)
	end
end

function find_plan_μ(mt::MultiType)
	pgrid, agrid = mt.ct.pgrid, mt.ct.agrid
	ωgrid, χgrid = mt.ωgrid, mt.χgrid

	mean_ω, mean_χ, mean_a = zeros(3)
	m2_ω, m2_χ, m2_a = zeros(3)

	sum_prob = sum(mt.μ)
	for (ja, av) in enumerate(agrid), (jχ, χv) in enumerate(χgrid), (jω, ωv) in enumerate(ωgrid)

		mean_ω += mt.μ[jω, jχ, ja] * ωv
		mean_χ += mt.μ[jω, jχ, ja] * annualized(χv)
		mean_a += mt.μ[jω, jχ, ja] * annualized(av)

		m2_ω += mt.μ[jω, jχ, ja] * ωv^2
		m2_χ += mt.μ[jω, jχ, ja] * annualized(χv)^2
		m2_a += mt.μ[jω, jχ, ja] * annualized(av)^2
	end

	mean_ω *= 1/sum_prob
	mean_χ *= 1/sum_prob
	mean_a *= 1/sum_prob
	m2_ω *= 1/sum_prob
	m2_χ *= 1/sum_prob
	m2_a *= 1/sum_prob

	sd_ω = sqrt(m2_ω - mean_ω^2)
	sd_χ = sqrt(m2_χ - mean_χ^2)
	sd_a = sqrt(m2_a - mean_a^2)

	return mean_ω, mean_χ, mean_a, sd_ω, sd_χ, sd_a
end

function find_equil!(mt::MultiType, z0=1e-2)
	mt.z = z0
	pgrid, agrid = mt.ct.pgrid, mt.ct.agrid
	ωgrid, χgrid = mt.ωgrid, mt.χgrid
	L_mat = mt.L_mat

	jp0 = floor(Int, length(mt.ct.pgrid)*0.9)

	k_max = mean(L_mat[:,:,1,:]) # mean L when p = 0 (should be constant across plans)
	k_min = minimum(L_mat[:,:,jp0,:]) # lower loss 
	V = var(L_mat[:,:,1,:])
	if V > 1e-4
		print_save("WARNING: variance of Lᴺ = $(@sprintf("%0.3g",V))")
	end

	knots = (ωgrid[end:-1:1], χgrid, pgrid, agrid)
	itp_L = interpolate(knots, L_mat[end:-1:1,:,:,:], Gridded(Linear()))

	res = Optim.optimize(
		k -> (eval_k_to_mu(mt, k, itp_L)-1)^2,
		k_min, k_max, GoldenSection())

	if res.minimum > 1e-4
		print_save("WARNING: Couldn't find μ at z = $zv")
	end

	k_star = res.minimizer

	mt.μ = eval_k_to_mu(mt, k_star, itp_L; get_mu = true)

	return k_star
end

function mimic_z(mt::MultiType, N=50)

	zgrid = range(mt.ct.pgrid[3], 0.9, length=N)

	data = zeros(N,6)
	datanames = ["ω", "χ", "a", "s_ω", "s_χ", "s_a"]

	for (jz, zv) in enumerate(zgrid)
		find_equil!(mt, zv)
		data[jz,:] .= find_plan_μ(mt)
		println(zv)
	end

	return data, datanames, zgrid
end
