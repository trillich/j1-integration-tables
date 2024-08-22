/*
521452|DEGE|101|3|08/25/2024|12/13/2024|FA2024|3|A|||R
518444|ASH|109A|2|08/25/2024|12/13/2024|FA2024|2|A|||R
525615|ASH|203A|1|08/25/2024|12/13/2024|FA2024|2|A|||R
526061|OBRN|100B|2|08/25/2024|12/13/2024|FA2024|3|A|||R

MC_PostRoomAssign() parameters:
	@id_num as int,
	@bldg_cde as varchar(4),
	@room_cde as varchar(4),
	@slot as int, -- moot, ignored
	@no_per_room as int, -- moot, ignored
	@meal_plan as varchar(2),
	@begins_dte as datetime,
	@ends_dte as datetime,
	@sess_cde as varchar(6), -- e.g. FA2024, SP2023
	@stat as varchar(1), -- A(ssignment) or R(emoval)
	@cancel_dte AS datetime,
	@cancel_rsn AS varchar(30)

 */

call mc_postroomassign(
    521452,'DEGE','101',3,999,'4','08/25/2024','12/13/2024','FA2024'|3|A|||R
);
