using PlotlyJS, Colors, ColorSchemes

col = [	"#1f77b4",  # muted blue
		"#ff7f0e",  # safety orange
		"#2ca02c",  # cooked asparagus green
		"#d62728",  # brick red
		"#9467bd",  # muted purple
		"#8c564b",  # chestnut brown
		"#e377c2",  # raspberry yogurt pink
		"#7f7f7f",  # middle gray
		"#bcbd22",  # curry yellow-green
		"#17becf"   # blue-teal
		]

function lines(ct::CrazyType, y_mat; dim::Int64=0, title::String="", showleg::Bool=false)
	if dim == 1
		xgrid = ct.pgrid
		zgrid = ct.agrid
		xtitle= "𝑝"
	elseif dim == 2
		xgrid = ct.agrid
		zgrid = ct.pgrid
		xtitle= "𝑎"
	else
		throw(error("wrong dim"))
	end
	Nz = length(zgrid)
	cvec = range(col[1], stop=col[2], length=Nz)
	l = Array{PlotlyBase.GenericTrace{Dict{Symbol,Any}}}(undef, Nz)
	for (jz, zv) in enumerate(zgrid)
		if dim == 1
			y_vec = y_mat[:, jz]
			name = "𝑎"
		elseif dim == 2
			y_vec = y_mat[jz, :]
			name = "𝑝"
		end
		name = name * " = $(@sprintf("%.2g", zv))"
		jz % 2 == 0 ? showleg_i = showleg : showleg_i = false
		l_new = scatter(;x=xgrid, y=y_vec, name = name, showlegend = showleg_i, marker_color=cvec[jz])
		l[jz] = l_new
	end
	p = plot([l[jz] for jz in 1:Nz], Layout(;title=title, xaxis_title=xtitle))
	return p
end

function plot_ct(ct::CrazyType, y_tuple, n_tuple; make_pdf::Bool=false, make_png::Bool=false)
	if length(y_tuple) != length(n_tuple)
		throw(error("Make sure # y's = # n's"))
	end

	N = length(y_tuple)
	pl = Array{PlotlyJS.SyncPlot,2}(undef, N, 2)
	for jj in 1:N
		pl[jj, 1] = lines(ct, y_tuple[jj], dim = 1, title=n_tuple[jj], showleg = (jj==1))
		pl[jj, 2] = lines(ct, y_tuple[jj], dim = 2, title=n_tuple[jj], showleg = (jj==1))
	end

	# p = hvcat(2, pl[:])

	relayout!(p, font_family = "Fira Sans Light", font_size = 12, plot_bgcolor="rgba(250, 250, 250, 1.0)", paper_bgcolor="rgba(250, 250, 250, 1.0)")

	function makeplot(p, ext::String)
		savefig(p, pwd() * "/../Graphs/ct" * ext)
	end

	if make_pdf
		makeplot(p, ".pdf")
	end
	if make_png
		makeplot(p, ".png")
	end

	return p
end

function plot_ct_pa(ct::CrazyType, y=ct.L, name="𝓛"; ytitle="")

	a_max = Nash(ct)
	jamax = findfirst(ct.agrid.>=a_max)

	colorpal = ColorSchemes.fall

	function set_col(ja, agrid, rel::Bool=false)
		weight = min(1,max(0,(ja-1)/(jamax-1)))
		if rel
			weight = min(1, agrid[ja] / a_max)
		end
		# return weighted_color_mean(weight, parse(Colorant,col[4]), parse(Colorant,col[1]))
		return get(colorpal, weight)
	end

	p1 = plot([
		scatter(;x=ct.pgrid, y=y[:,ja], marker_color=set_col(ja,ct.agrid), name = "a=$(@sprintf("%.3g", annualized(av)))") for (ja,av) in enumerate(ct.agrid) if av <= a_max
		], Layout(;title=name, fontsize=16,font_family="Fira Sans Light", xaxis_zeroline=false, xaxis_title= "𝑝", yaxis_title=ytitle))
	return p1
end

function makeplots_ct(ct::CrazyType; make_pdf::Bool=false, make_png::Bool=false)

	gπ_over_a = zeros(size(ct.gπ))
	Ep_over_p = zeros(size(ct.Ep))
	for (jp, pv) in enumerate(ct.pgrid), (ja,av) in enumerate(ct.agrid)
		gπ_over_a[jp, ja] = ct.gπ[jp, ja] - av
		Ep_over_p[jp, ja] = ct.Ep[jp, ja] - pv
	end

	p1 = plot_ct(ct, (ct.gπ, ct.L), ("gπ", "𝓛"); make_pdf=make_pdf, make_png=make_png)

	p2 = plot_ct(ct, (ct.Ey, ct.Eπ), ("𝔼y", "𝔼π"); make_pdf=make_pdf, make_png=make_png)

	p3 = plot_ct(ct, (gπ_over_a, Ep_over_p), ("gπ-a", "𝔼p'-p"); make_pdf=make_pdf, make_png=make_png)

	return p1, p2, p3
end

function makeplots_ct_pa(ct::CrazyType)

	gπ_over_a = zeros(size(ct.gπ))
	Ep_over_p = zeros(size(ct.Ep))
	for (jp, pv) in enumerate(ct.pgrid), (ja,av) in enumerate(ct.agrid)
		gπ_over_a[jp, ja] = ct.gπ[jp, ja] - av
		Ep_over_p[jp, ja] = ct.Ep[jp, ja] - pv
	end

	annual_π = annualized.(gπ_over_a)

	pL = plot_ct_pa(ct, ct.L, "𝓛")
	pπ = plot_ct_pa(ct, annual_π, "gπ-a", ytitle="%")
	py = plot_ct_pa(ct, ct.Ey, "𝔼y")
	pp = plot_ct_pa(ct, Ep_over_p, "𝔼p'-p")

	p = [pL pπ; py pp]

	relayout!(p, font_family = "Fira Sans Light", font_size = 16, plot_bgcolor="rgba(250, 250, 250, 1.0)", paper_bgcolor="rgba(250, 250, 250, 1.0)")

	return p
end


function plot_simul(ct::CrazyType; T::Int64=50, N=1000, jp0::Int64=2, noshocks::Bool=false)
	# Update simulations codes
	include("simul.jl")

	p_mat, a_mat, π_mat, y_mat, g_mat = zeros(T,N), zeros(T,N), zeros(T,N), zeros(T,N), zeros(T,N)

	for jn in 1:N
	    p_vec, a_vec, π_vec, y_vec, g_vec = simul(ct; T=T, noshocks=noshocks)
	    p_mat[:,jn] = p_vec
	    a_mat[:,jn], π_mat[:,jn], y_mat[:,jn], g_mat[:,jn] = annualized.(a_vec), annualized.(π_vec), annualized.(y_vec), annualized.(g_vec)
	end

	# k = 2
	# quantiles = linspace(0,1, k+2)
	quantiles = [0.25; 0.75]
	k = length(quantiles)
	p_qnt, a_qnt, π_qnt, y_qnt, g_qnt = zeros(T,k), zeros(T,k), zeros(T,k), zeros(T,k), zeros(T,k)
	for jk in 1:k
	    for jt in 1:T
	        qnt = quantiles[jk]
	        p_qnt[jt,jk], a_qnt[jt,jk], π_qnt[jt,jk], y_qnt[jt,jk], g_qnt[jt,jk] = quantile(p_mat[jt, :], qnt), quantile(a_mat[jt, :], qnt), quantile(π_mat[jt, :], qnt), quantile(y_mat[jt, :], qnt), quantile(g_mat[jt, :], qnt)
	    end
	end
	p_med, a_med, π_med, y_med, g_med = vec(median(p_mat, dims=2)), vec(median(a_mat, dims=2)), vec(median(π_mat, dims=2)), vec(median(y_mat, dims=2)), vec(median(g_mat, dims=2))
	p_avg, a_avg, π_avg, y_avg, g_avg = vec(mean(p_mat, dims = 2)), vec(mean(a_mat, dims = 2)), vec(mean(π_mat, dims = 2)), vec(mean(y_mat, dims = 2)), vec(mean(g_mat, dims = 2))

	prep = plot([
			[scatter(;x=1:T, y=p_qnt[:,jk], showlegend=false, opacity=0.25, line_color=col[1]) for jk in 1:k]
			scatter(;x=1:T, y=p_avg, showlegend=false, line_color=col[1])
			scatter(;x=1:T, y=p_med, showlegend=false, line_color=col[1], line_dash="dashdot")
			], Layout(;title="Reputation", font_family = "Fira Sans Light", font_size = 16))
	ptar = plot([
			[scatter(;x=1:T, y=a_qnt[:,jk], showlegend=false, opacity=0.25, line_color=col[2]) for jk in 1:k]
			scatter(;x=1:T, y=a_avg, showlegend=false, line_color=col[2])
			scatter(;x=1:T, y=a_med, showlegend=false, line_color=col[2], line_dash="dashdot")
			], Layout(;title="Target", font_family = "Fira Sans Light", font_size = 16))
	pinf = plot([
			[scatter(;x=1:T, y=π_qnt[:,jk], showlegend=false, opacity=0.25, line_color=col[3]) for jk in 1:k]
			scatter(;x=1:T, y=π_avg, showlegend=false, line_color=col[3])
			scatter(;x=1:T, y=π_med, showlegend=false, line_color=col[3], line_dash="dashdot")
			scatter(;x=1:T, y=g_avg, showlegend=false, line_color=col[5], line_dash="dot")
			], Layout(;title="Inflation", font_family = "Fira Sans Light", font_size = 16))
	pout = plot([
			[scatter(;x=1:T, y=y_qnt[:,jk], showlegend=false, opacity=0.25, line_color=col[4]) for jk in 1:k]
			scatter(;x=1:T, y=y_avg, showlegend=false, line_color=col[4])
			scatter(;x=1:T, y=y_med, showlegend=false, line_color=col[4], line_dash="dashdot")
			], Layout(;title="Output", font_family = "Fira Sans Light", font_size = 16))
	p = [prep ptar; pinf pout]

	relayout!(p, font_family="Fira Sans Light")

    return p
end

function makeplot_conv(dists::Vector; switch_η=25)
	T = length(dists)

	function MA_t(t::Int64)
		return [100*mean(dists[jt-t:jt]) for jt in (t+1):T]
	end

	shapes = [vline(xchange, line_dash="dot", line_width=1, line_color="black") for xchange in 1:T if xchange%switch_η==0]

	push!(shapes, hline(5e-4*100, line_dash="dash", line_width=1, line_color="black"))
	
	yvec = MA_t(0)
	ls = [scatter(;x=1:T, y=yvec, showlegend=false)]
	push!(shapes, hline(minimum(yvec), line_dash="dash", line_width=1, line_color=col[1]) )
	
	if T > 11
		yvec = MA_t(10)
		push!(ls, scatter(;x=5:T-5, y=yvec, showlegend=false))
		push!(shapes, hline(minimum(yvec), line_dash="dash", line_width=1, line_color=col[2]))
		if T > 51
			yvec = MA_t(50)
			push!(ls, scatter(;x=25:T-25, y=yvec, showlegend=false))
			push!(shapes, hline(minimum(yvec), line_dash="dash", line_width=1, line_color=col[3]))
			if T > 101
				yvec = MA_t(100)
				push!(ls, scatter(;x=50:T-50, y=yvec, showlegend=false))
				push!(shapes, hline(minimum(yvec), line_dash="dash", line_width=1, line_color=col[4]))
			end
		end
	end
	p1 = plot(ls, Layout(;shapes = shapes))

	relayout!(p1, yaxis_type="log", title="‖g′-g‖/‖g‖", xaxis_title="iterations", yaxis_title="%")
	return p1
end