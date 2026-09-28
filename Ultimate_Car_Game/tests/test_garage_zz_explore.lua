return {
	{ "explore", function(T, H)
		for _, mode in ipairs({"base","src"}) do
		print("=== " .. mode)
		local g = H.Garage({ scripts = mode })
		local p = g:Join(1001)
		local c = g:StartClient(p)
		g:Advance(1)
		local sunk = g:Key(p, Enum.KeyCode.Tab)
		g:Advance(0.3)
		print("tab sunk", sunk, "tablet visible", g:FindGui(p, "/ ULTIMATE CAR GAME") ~= nil)
		local offer
		for _, o in ipairs(g:State(p).data.offers) do if o.kind == "inspection" then offer = o end end
		g:Send(p, "accept", { id = offer.id }); g:Advance(0.2)
		local job = g:State(p).data.jobs[1]
		g:Send(p, "target", { id = job.id, car = true }); g:Send(p, "scan", { id = job.id }); g:Advance(3)
		g:Send(p, "diagnose", { id = job.id, choice = 2 }); g:Advance(0.3)
		local closeBtn = g:FindGui(p, "Schließen", {class="TextButton"})
		if closeBtn then g:Click(closeBtn) end
		local car = g:Car(p, job.id)
		g:Teleport(p, car.EnginePoint, Vector3.new(0, 0, 2))
		g:Advance(0.5)
		local va = g:FindGui(p, function(x) return x.Name == "VehicleAction_E" end)
		print("vehicle action E", va and va.Text)
		local m = g:Mark()
		g:Click(va)
		local ch = g:Last(p, "challenge", m)
		print("challenge", ch ~= nil, "modal", g:FindGui(p, "Präzise arbeiten") ~= nil)
		g:AdvanceTo(ch.startAt + 0.93)
		m = g:Mark()
		local s2 = g:Key(p, Enum.KeyCode.Space)
		print("space sunk", s2, "hit sent", (function() for _, a in ipairs(g:Remote("Command").__data.sentToServer) do if a[1] == "hit" then return a[2].at end end end)())
		print("toasts", table.concat(g:Toasts(p, m), " | "))
		g:Advance(0.5)
		print("phase", g:State(p).data.jobs[1].phase, "modal gone", g:FindGui(p, "Präzise arbeiten") == nil)
		print("errors", g:ErrorText())
		print("warnings", table.concat(g:Warnings(), " | "))
		end
	end },
}
