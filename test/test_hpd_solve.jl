using Revise
using mitamp

graph = solve_hpd("test/hpd/domain.hpd", "test/hpd/problem.hpd"; max_levels=100)
# 1