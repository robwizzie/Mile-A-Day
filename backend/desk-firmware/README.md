# Desk box firmware

`firmware.uf2` is the newest build of the desk counter (CircuitPython 10.3.1 +
the frozen `mad` package from `desk/firmware/mad`). `firmware.json` says which
version it is. Desk owners download it from the remote (Admin -> Desks ->
Update your box) and drag it onto their box's MATRIXBOOT drive.

To publish a new build: bump `FIRMWARE` in `desk/firmware/mad/app.py`, build
the UF2, replace `firmware.uf2`, and bump `version` / `notes` here.
