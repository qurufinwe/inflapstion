using PlotlyJS, Colors, ColorSchemes, Printf, ORCA
include("type_def.jl")

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

function style_plot!(pl; slides::Bool=true)
	if slides
		relayout!(pl,
			font_family = "Lato", font_size=14,
			paper_bgcolor="#fafafa", plot_bgcolor="#fafafa"
			)
	else
		relayout!(pl,
			font_family = "Linux Libertine", font_size=14,
			paper_bgcolor="white", plot_bgcolor="white"
			)
	end
	nothing
end

function lines(ct::CrazyType, y_mat; dim::Int64=0, title::String="", showleg::Bool=false)
	if dim == 1
		xgrid = ct.pgrid
		zgrid = ct.agrid
		xtitle= "<i>p</i>"
	elseif dim == 2
		xgrid = ct.agrid
		zgrid = ct.pgrid
		xtitle= "<i>a"
	else
		throw(error("wrong dim"))
	end
	Nz = length(zgrid)
	cvec = range(col[1], stop=col[2], length=Nz)
	l = Array{PlotlyBase.GenericTrace{Dict{Symbol,Any}}}(undef, Nz)
	for (jz, zv) in enumerate(zgrid)
		if dim == 1
			y_vec = y_mat[:, jz]
			name = "<i>a"
		elseif dim == 2
			y_vec = y_mat[jz, :]
			name = "<i>p</i>"
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

function plot_ct_pa(ct::CrazyType, y=ct.L, name="𝓛"; ytitle="", reverse_draw::Bool=false, positive_p::Bool=false, few_lines::Bool=false)

	a_max = Nash(ct)
	jamax = findfirst(ct.agrid.>=a_max)
	positive_p ? xvec = ct.pgrid[2:end] : xvec = ct.pgrid
	positive_p ? y = y[2:end, :] : nothing

	few_lines ? step_a = 2 : step_a = 1

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
		scatter(;x=xvec, y=y[:,ja], marker_color=set_col(ja,ct.agrid), name = "a=$(@sprintf("%.3g", annualized(ct.agrid[ja])))") for ja in 1:step_a:length(ct.agrid) if ct.agrid[ja] <= a_max
		], Layout(;title=name, fontsize=16,font_family="Fira Sans Light", xaxis_zeroline=false, xaxis_title= "<i>p</i>", yaxis_title=ytitle))

	if reverse_draw
		p1 = plot([
			scatter(;x=xvec, y=y[:,ja], marker_color=set_col(ja,ct.agrid), showlegend=false, name = "a=$(@sprintf("%.3g", annualized(ct.agrid[ja])))") for ja in length(ct.agrid):-1:1 if ct.agrid[ja] <= a_max
			], Layout(;title=name, fontsize=16,font_family="Fira Sans Light", xaxis_zeroline=false, xaxis_title= "<i>p</i>", yaxis_title=ytitle))
	end

	return p1
end

function makeplots_ct(ct::CrazyType; make_pdf::Bool=false, make_png::Bool=false)

	gπ_minus_a = zeros(size(ct.gπ))
	Ep_minus_p = zeros(size(ct.Ep))
	for (jp, pv) in enumerate(ct.pgrid), (ja,av) in enumerate(ct.agrid)
		gπ_minus_a[jp, ja] = ct.gπ[jp, ja] - av
		Ep_minus_p[jp, ja] = ct.Ep[jp, ja] - pv
	end

	p1 = plot_ct(ct, (ct.gπ, ct.L), ("gπ", "𝓛"); make_pdf=make_pdf, make_png=make_png)

	p2 = plot_ct(ct, (ct.Ey, ct.Eπ), ("𝔼y", "𝔼π"); make_pdf=make_pdf, make_png=make_png)

	p3 = plot_ct(ct, (gπ_minus_a, Ep_minus_p), ("gπ-a", "𝔼[<i>p'-p</i>]"); make_pdf=make_pdf, make_png=make_png)

	return p1, p2, p3
end

function makeplots_ct_pa(ct::CrazyType; slides::Bool=true)
	""" Currently run for paper on ct.ω = 0.01, ct.χ = 0 """
	gπ_minus_a = zeros(size(ct.gπ))
	Eπ_minus_a = zeros(size(ct.gπ))
	Ep_minus_p = zeros(size(ct.Ep))
	for (jp, pv) in enumerate(ct.pgrid), (ja,av) in enumerate(ct.agrid)
		gπ_minus_a[jp, ja] = ct.gπ[jp, ja] - av
		Eπ_minus_a[jp, ja] = pv*av + (1.0-pv)*ct.gπ[jp, ja] - av
		Ep_minus_p[jp, ja] = ct.Ep[jp, ja] - pv
	end

	if slides
		font = "Lato"
		bgcol = "#fafafa"
		heights = 500 * ones(4)
	else
		font = "Linux Libertine"
		bgcol = "white"
		heights = [450, 350, 400, 500]
	end

	annual_π = annualized.(gπ_minus_a)
	Eπ_a 	 = annualized.(Eπ_minus_a)

	pL = plot_ct_pa(ct, ct.L, "𝓛"; reverse_draw=true)
	pπ = plot_ct_pa(ct, annual_π, "<i>g<sup>⋆</sup> - a", ytitle="%")
	pE = plot_ct_pa(ct, Eπ_a, "𝔼π-a", ytitle="%")
	py = plot_ct_pa(ct, ct.Ey, "𝔼y")
	pp = plot_ct_pa(ct, Ep_minus_p, "𝔼[<i>p'-p</i>]")
	pC = plot_ct_pa(ct, ct.C, "𝓒")

	p = [pL pπ; py pp]

	relayout!(p, font_family = font, font_size = 16, plot_bgcolor=bgcol, paper_bgcolor=bgcol)
	relayout!(pL, font_family = font, font_size = 16, plot_bgcolor=bgcol, paper_bgcolor=bgcol, height = heights[1])

	relayout!(pπ, font_family=font, xaxis_title="<i>p", yaxis_title="%", font_size=16, width=900, height=heights[2], plot_bgcolor=bgcol, paper_bgcolor=bgcol)
	restyle!(pπ, showlegend=false)

	relayout!(pp, font_family=font, xaxis_title="<i>p", font_size=16, width=900, height=heights[3], plot_bgcolor=bgcol, paper_bgcolor=bgcol)
	restyle!(pp, showlegend=false)

	return p, pL, pπ, pC, pp
end


function plot_simul(ct::CrazyType; T::Int64=50, N=10000, jp0::Int64=3, noshocks::Bool=false, CIs::Bool=false)
	# Update simulations codes
	include("simul.jl")

	p_mat, a_mat, π_mat, y_mat, g_mat, L_mat = zeros(T,N), zeros(T,N), zeros(T,N), zeros(T,N), zeros(T,N), zeros(T,N)

	for jn in 1:N
	    p_vec, a_vec, π_vec, y_vec, g_vec, L_vec = simul(ct; jp0=jp0, T=T, noshocks=noshocks)
	    p_mat[:,jn] = p_vec
	    L_mat[:,jn] = L_vec
	    a_mat[:,jn], π_mat[:,jn], y_mat[:,jn], g_mat[:,jn] = annualized.(a_vec), annualized.(π_vec), annualized.(y_vec), annualized.(g_vec)
	end

	# k = 2
	# quantiles = linspace(0,1, k+2)
	quantiles = [0.25; 0.75]
	k = length(quantiles)
	p_qnt, a_qnt, π_qnt, y_qnt, g_qnt, L_qnt = zeros(T,k), zeros(T,k), zeros(T,k), zeros(T,k), zeros(T,k), zeros(T,k)
	for jk in 1:k
	    for jt in 1:T
	        qnt = quantiles[jk]
	        p_qnt[jt,jk], a_qnt[jt,jk], π_qnt[jt,jk], y_qnt[jt,jk], g_qnt[jt,jk], L_qnt[jt,jk] = quantile(p_mat[jt, :], qnt), quantile(a_mat[jt, :], qnt), quantile(π_mat[jt, :], qnt), quantile(y_mat[jt, :], qnt), quantile(g_mat[jt, :], qnt), quantile(L_mat[jt, :], qnt)
	    end
	end
	p_med, a_med, π_med, y_med, g_med, L_med = vec(median(p_mat, dims=2)), vec(median(a_mat, dims=2)), vec(median(π_mat, dims=2)), vec(median(y_mat, dims=2)), vec(median(g_mat, dims=2)), vec(median(L_mat, dims=2))
	p_avg, a_avg, π_avg, y_avg, g_avg, L_avg = vec(mean(p_mat, dims = 2)), vec(mean(a_mat, dims = 2)), vec(mean(π_mat, dims = 2)), vec(mean(y_mat, dims = 2)), vec(mean(g_mat, dims = 2)), vec(mean(L_mat, dims = 2))

	prep = plot([
			[scatter(;x=(1:T)/4, y=p_qnt[:,jk], showlegend=false, opacity=0.25, line_color=col[1]) for jk in 1:k if CIs]
			scatter(;x=(1:T)/4, y=p_avg, showlegend=false, line_color=col[1])
			scatter(;x=(1:T)/4, y=p_med, showlegend=false, line_color=col[1], line_dash="dashdot")
			], Layout(;title="Reputation", yaxis_zeroline=false, font_family = "Fira Sans Light", font_size = 16))
	ptar = plot([
			[scatter(;x=(1:T)/4, y=a_qnt[:,jk], showlegend=false, opacity=0.25, line_color=col[2]) for jk in 1:k if CIs]
			scatter(;x=(1:T)/4, y=a_avg, showlegend=false, line_color=col[2])
			scatter(;x=(1:T)/4, y=g_avg, showlegend=false, line_color=col[5], line_dash="dot")
			# scatter(;x=(1:T)/4, y=a_med, showlegend=false, line_color=col[2], line_dash="dashdot")
			], Layout(;title="Target", yaxis_zeroline=false, font_family = "Fira Sans Light", font_size = 16))
	pinf = plot([
			[scatter(;x=(1:T)/4, y=π_qnt[:,jk], showlegend=false, opacity=0.25, line_color=col[3]) for jk in 1:k if CIs]
			scatter(;x=(1:T)/4, y=π_avg, showlegend=false, line_color=col[3])
			scatter(;x=(1:T)/4, y=π_med, showlegend=false, line_color=col[3], line_dash="dashdot")
			scatter(;x=(1:T)/4, y=g_avg, showlegend=false, line_color=col[5], line_dash="dot")
			], Layout(;title="Inflation", yaxis_zeroline=false, font_family = "Fira Sans Light", font_size = 16))
	pout = plot([
			[scatter(;x=(1:T)/4, y=y_qnt[:,jk], showlegend=false, opacity=0.25, line_color=col[4]) for jk in 1:k if CIs]
			scatter(;x=(1:T)/4, y=y_avg, showlegend=false, line_color=col[4])
			scatter(;x=(1:T)/4, y=y_med, showlegend=false, line_color=col[4], line_dash="dashdot")
			], Layout(;title="Output", yaxis_zeroline=false, font_family = "Fira Sans Light", font_size = 16))
	p = [prep ptar; pinf pout]

	relayout!(p, font_family = "Fira Sans Light", font_size = 14, plot_bgcolor="rgba(250, 250, 250, 1.0)", paper_bgcolor="rgba(250, 250, 250, 1.0)")

	pL = plot([
		scatter(;x=(1:T)/4, y=L_avg, showlegend=false, line_color=col[4])
		scatter(;x=(1:T)/4, y=L_med, showlegend=false, line_color=col[4], line_dash="dashdot")
		], Layout(;title="𝓛", font_family = "Fira Sans Light", font_size = 16))

    return p, pL
end

function makeplot_conv(dists::Vector; switch_η=25)
	T = length(dists)

	function MA_t(t::Int64)
		return [100*mean(dists[jt-t:jt]) for jt in (t+1):T]
	end

	shapes = [vline(xchange, line_dash="dot", line_width=1, line_color="black") for xchange in 1:T if xchange%switch_η==0]

	push!(shapes, hline(25e-4*100, line_dash="dash", line_width=1, line_color="black"))
	
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

plot_L_contour(mt::MultiType; name_y="𝓛", slides=false) = plot_L_contour(mt.ωgrid, mt.χgrid, mt.L_mat; name_y=name_y, slides=slides)

function plot_L_contour(ωgrid, χgrid, L_mat; name_y="𝓛", slides::Bool=false)

	L_filled, temp = findmin(L_mat[.!isnan.(L_mat)])
	jjxy = findfirst(L_mat.==L_filled)

	# _, jjxy = findmin(L_mat)
	
	xmin = perc_rate(ωgrid[jjxy[1]])
	ymin = annualized(χgrid[jjxy[2]])

	if name_y == "𝓛"
		title = "lim<sub><i>p→0</i></sub> min<sub><i>a</i></sub> 𝓛(<i>p,a,ω,χ</i>)"
		shape_vec = [attr(;x0=xmin-0.001, x1 = xmin+0.001, y0 = ymin-0.002, y1=ymin+0.002, line_color="red", type="circle")]
	elseif name_y == "C"
		title = "lim<sub><i>p→0</i></sub> C(<i>p,a*,ω,χ</i>)"
		shape_vec = []
	end

	ctχω = contour(;
		x = perc_rate(ωgrid), y = annualized.(χgrid),
		z = L_mat,
		# contours_coloring="heatmap",
		# contours_start=tickmin, contours_end=tickmax,
		# colorbar_tick0 = 0., colorbar_dtick=floor(Int, 1./5),
		colorscale = "Electric", reversescale = true,
		# colorbar_dtick=0.1, colorbar_xpad=14
		)
	p1 = plot(ctχω, Layout(;title=title, xaxis_title="Decay rate  (<i> %</i>)", yaxis_title="Asymptote  (<i>χ</i>)", shapes = shape_vec))
	if slides
		relayout!(p1, font_family = "Lato", font_size = 16, plot_bgcolor="rgba(250, 250, 250, 1.0)", paper_bgcolor="rgba(250, 250, 250, 1.0)")
	end

	return p1
end

function plot_announcements(;slides::Bool=true, exts::Vector=[], cond::Bool=false, add_opt::Bool=false, cond_t::Bool=false)
	xvec = 0:0.25:10

	cond_t ? cond = true : nothing

	slides ? colorpal = ColorSchemes.munch : colorpal = ColorSchemes.southwest

	line_opt = scatter(;x=xvec, y=((1.750133)-(0.784)) * exp.(-0.4951.*(4.0.*xvec)).+(0.784), showlegend=false, marker_color="#d62728", line_width=3, line_dash="dash")

	lines = [scatter(;x=xvec, y=(a0-χ) * exp.(-ω.*(xvec)).+χ, showlegend=false, marker_color=get(colorpal, χ/2)) for a0 in range(0,2, length=5) for ω in range(0,0.8,length=3) for (jχ, χ) in enumerate(range(2,0,length=5)) if ω != 0.0]

	plotname = "announcements"
	annotations = []
	if cond
		lines = [lines[43]]
		plotname *= "_cond"
		te = 9*4+1
		xe = lines[1][:x][te]
		ye = lines[1][:y][te]
		col_line = lines[1][:marker][:color]
		push!(annotations, attr(; x=xe, y=ye+0.05, text="<i>c", font_color=col_line, showarrow=false))
	end

	if add_opt
		push!(lines, line_opt)
		plotname *= "_w_opt"
	end

	shapes = []
	if cond_t
		tt = 11
		x0 = lines[1][:x][tt]
		y0 = lines[1][:y][tt]
		shapes = [vline(x0, line_dash = "dash"); attr(;x0=x0-1*0.03, x1 = x0+1*0.03, y0 = y0-1*0.01, y1=y0+1*0.01, line_color=get(ColorSchemes.darkrainbow, 0.12), fillcolor=get(ColorSchemes.darkrainbow, 0.12), type="circle")]
		push!(annotations,attr(; x=x0 + 0.05, y=y0 + 0.01, text="<i>a<sub>t</sub><sup>c</sup>", ax=35, font_color = get(ColorSchemes.darkrainbow, 0.12), font_size=24, font_family="Lato"))
		plotname *="_t"
	end

	p1 = plot(lines, Layout(;xaxis_zeroline=false, yaxis_zeroline=false, xaxis_title="Years", yaxis_range=[-0.1;2.1], yaxis_title="%", title="Inflation announcements", shapes = shapes, annotations=annotations)
		)

	if slides
		relayout!(p1, font_family = "Lato", font_size = 18, plot_bgcolor="rgba(250, 250, 250, 1.0)", paper_bgcolor="rgba(250, 250, 250, 1.0)")
		plotname *= "_slides"
	else
		relayout!(p1, font_family = "STIX Two Text", font_size = 18, height = 500, width=1000)
		plotname *= "_paper"
	end

	if length(exts) > 0
		for (jj, ext) in enumerate(exts)
			savefig(p1, pwd()*"/../Graphs/"*plotname*"."*ext)
		end
		return nothing
	end

	return p1
end


function plot_bayes(; center=1.5, dist=0.5, σ=0.5, p=0.25, distplot=4*sqrt(dist))

	a = center-dist
	g = center+dist

	ϵ_vec = range(center-distplot, center+distplot, length=1001)

	fa(x) = pdf.(Normal(0,σ), x .- a)
	fg(x) = pdf.(Normal(0,σ), x .- g)

	Bayes(p,x) = p .+ p.*(1.0.-p) .* (fa(x) .- fg(x)) ./ (p.*fa(x) .+ (1.0.-p).*fg(x))

	_, jj = findmin((fa(ϵ_vec) - fg(ϵ_vec)).^2)
	ϵstar = ϵ_vec[jj]

	shapes = [vline(ϵstar, fa(ϵstar), Bayes(p,ϵstar), line_dash="dashdot")]
	annotations = [attr(x=ϵstar, xanchor="left", y=(Bayes(p,ϵstar)+fa(ϵstar))/2, yanchor="center", text="π*", showarrow=false)]

	p1 = plot([
		scatter(;x=ϵ_vec, y=fa(ϵ_vec), name="<i>f(a-π)")
		scatter(;x=ϵ_vec, y=fg(ϵ_vec), name="<i>f(g-π)")
		scatter(;x=ϵ_vec, y=Bayes(p,ϵ_vec), name="<i>B(p,π,a,g)", line_width=2)
		],
		Layout(;yaxis_range=[-0.05;1.05], xaxis_range=[0,3], shapes=shapes, annotations=annotations)
		)

	relayout!(p1, font_family = "Lato", font_size = 16, plot_bgcolor="rgba(250, 250, 250, 1.0)", paper_bgcolor="rgba(250, 250, 250, 1.0)", width=1200, height=500)


	return p1
end

plot_plans_p(mt::MultiType; decay::Bool=true, make_pdf::Bool=false) = plot_plans_p(mt.ct, mt.L_mat, mt.ωgrid, mt.χgrid, decay=decay, make_pdf=make_pdf)
function plot_plans_p(ct::CrazyType, L_mat, ωgrid, χgrid; decay::Bool=true, make_pdf::Bool=false)

	ωvec = zeros(ct.Np)
	avec = zeros(ct.Np)
	χvec = zeros(ct.Np)

	data = zeros(ct.Np,3)
	for jp in 1:ct.Np
		_, jj = findmin(L_mat[:,:,jp,:])

		if decay
			data[jp, 1] = perc_rate(ωgrid[jj[1]])
		else
			data[jp, 1] = ωgrid[jj[1]]
		end
		data[jp, 2] = annualized.(ct.agrid[jj[3]])
		data[jp, 3] = annualized.(χgrid[jj[2]])
	end


	datanames = ["ω", "a", "χ"]
	cols = [get(ColorSchemes.southwest, jj) for jj in [0, 0.5, 1]]
	ls = Vector{PlotlyBase.GenericTrace{Dict{Symbol,Any}}}(undef, 0)

	yax = ["y2", "y1", "y1"]
	for jj in 1:3
		col = cols[jj]
		push!(ls, scatter(;x=ct.pgrid[3:end], y=data[3:end, jj], line_width = 2.5, yaxis="<i>"*yax[jj], marker_color=col, name="<i>"*datanames[jj]*"</i>"))
	end

	layout = Layout(
		yaxis = attr(domain=[0, 0.45], zeroline=false),
		yaxis2 = attr(domain=[0.55, 1], zeroline=false),
		xaxis = attr(zeroline=false),
		legend = attr(orientation="h", x=0.05),
		font_size=16, font_family="Linux Libertine"
		)

	p1 = plot(ls, layout)

	# pω = plot(scatter(;x=ct.pgrid[3:end], y=ωvec[3:end], line_width=2.5, name="<i>ω", marker_color=get(ColorSchemes.southwest, 0.0)));
	# pχa= plot([
	# 	scatter(;x=ct.pgrid[3:end], y=annualized.(avec[3:end]), line_width=2.5, name="<i>a", marker_color=get(ColorSchemes.southwest, 0.5))
	# 	scatter(;x=ct.pgrid[3:end], y=annualized.(χvec[3:end]), line_width=2.5, name="<i>χ", marker_color=get(ColorSchemes.southwest, 0.99))
	# 	], Layout(;yaxis_title="%", xaxis_title="<i>p</i>"));

	# relayout!(pω,  xaxis_zeroline=false, yaxis_zeroline=false)
	# relayout!(pχa, xaxis_zeroline=false, yaxis_zeroline=false)

	# p1 = [pω; pχa]
	relayout!(p1, plot_bgcolor="rgba(250, 250, 250, 1.0)", paper_bgcolor="rgba(250, 250, 250, 1.0)", title="Preferred plans")
	relayout!(p1, height=600, width=900, font_family="Lato", legend=attr(;orientation="h", x=0.1))

	if make_pdf
		savefig(p1, pwd()*"/../Graphs/plans.pdf")
	end
	return p1
end

function make_colorbar(ct::CrazyType; slides::Bool=true)
	agr = annualized.(ct.agrid)
	Na = length(ct.agrid)

	p1 = plot(contour(;x=range(0,1,length=2), y=range(0,1,length=Na), z=[jy for jx in 1:2, jy in agr], colorscale=[[vv, get(ColorSchemes.fall, vv)] for vv in range(0,1,length=Na)], colorbar=attr(title="<i>a"), contours_coloring="heatmap"))

	if slides
		relayout!(p1, font_family="Lato", font_size=18, plot_bgcolor="rgba(250, 250, 250, 1.0)", paper_bgcolor="rgba(250, 250, 250, 1.0)")
	else
		relayout!(p1, font_family = "Linux Libertine", font_size=18)
	end
	return p1

end

function plot_mimic_z(mt::MultiType, N=50; slides::Bool=true, decay::Bool=true, CIs::Bool=false)

	data, datanames, zgrid = mimic_z(mt, N, decay=decay)

	cols = [get(ColorSchemes.southwest, jj) for jj in [0, 0.5, 1]]
	ls = Vector{PlotlyBase.GenericTrace{Dict{Symbol,Any}}}(undef, 0)

	yax = ["y2", "y1", "y1"]
	for jj in 1:3
		col = cols[jj]
		if CIs
			push!(ls, scatter(;x = zgrid, y = data[:,jj]+data[:,jj+3], yaxis=yax[jj], marker_color=col, mode="lines", opacity = 0.5, showlegend=false, line_width=0.01, hoverinfo="skip"))
			push!(ls, scatter(;x = zgrid, y = data[:,jj]-data[:,jj+3], yaxis=yax[jj], marker_color=col, mode="lines", opacity = 0.5, fill="tonexty", showlegend=false, line_width=0.01, hoverinfo="skip"))
		end
		push!(ls, scatter(;x=zgrid, y=data[:, jj], yaxis=yax[jj], marker_color=col, name="𝔼[<i>"*datanames[jj]*"</i>]"))
	end

	layout = Layout(
		yaxis = attr(domain=[0, 0.45], zeroline=false),
		yaxis2 = attr(domain=[0.55, 1], zeroline=false),
		xaxis = attr(zeroline=false),
		legend = attr(orientation="h", x=0.05),
		font_size=16, font_family="Linux Libertine"
		)

	p1 = plot(ls, layout)

	if slides
		relayout!(p1, font_family="Lato", paper_bgcolor="#fafafa", plot_bgcolor="#fafafa")
	end
	return p1
end

function save_plot_mimic_z(mt::MultiType, N=50; slides::Bool=true, CIs::Bool=false)
	p1 = plot_mimic_z(mt, N; slides=slides, CIs=CIs)
	savejson(p1, "../Graphs/tests/mimics$(ifelse(CIs, "_CI", "")).json")
	nothing
end
