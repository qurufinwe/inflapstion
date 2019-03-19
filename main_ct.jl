using Distributed

@everywhere include("type_def.jl")
@everywhere include("ct.jl")
@everywhere include("reporting_routines.jl")
@everywhere include("simul.jl")
@everywhere include("plotting_routines.jl")

write(pwd()*"/../output.txt", "")

function establish_remote()
	machine_name = ""
	try
		machine_name = read("/name.txt", String)
	catch
	end
	return !(machine_name=="qlaptop")
end
machine_remote = establish_remote()

ct = CrazyType(ω = 0.0);
initial_report(ct)

Epfi!(ct, tol=1e-3, tempplots=true)


#=
L_mat, ωmin, p1 = choose_ω(; remote = machine_remote)
p1
=#