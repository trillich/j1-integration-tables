#!/usr/bin/perl -w

while ( <DATA> ) {
    chomp;
    my ($thd_id, $thd_bldg, $thd_room, $thd_slot, $thd_start, $thd_end, $thd_term,
        $thd_no_per_room, $thd_stat, $thd_cancel_date, $thd_cancel_reason) = split /[|]/;
    
    print <<SQL;
DECLARE	\@return_value int,
		\@outtransid   int
EXEC	\@return_value = [dbo].[MC_PostRoomAssign]
		\@trans_id     = 1,
		\@id_num       = $thd_id,
		\@bldg_cde     = N'$thd_bldg',
		\@room_cde     = N'$thd_room',
		\@slot         = $thd_slot,
		\@no_per_room  = $thd_no_per_room,
		\@meal_plan    = N'AA',
		\@begins_dte   = '$thd_start',
		\@ends_dte     = '$thd_end',
		\@sess_cde     = N'FA2024',
		\@stat         = N'A',
		\@cancel_dte   = '$thd_cancel_date',
		\@cancel_rsn   = '$thd_cancel_reason',
		\@outtransid   = \@outtransid OUTPUT
SELECT	\@outtransid as N'\@outtransid'
;

SQL
    # print "exec MC_PostRoomAssign
    #     $thd_id, '$thd_bldg', '$thd_room', $thd_slot, $thd_no_per_room,
    #     4, '$thd_start', '$thd_end', '$thd_term', '$thd_stat', '$thd_cancel_date', '$thd_cancel_reason'
    # ;\n"
}
__DATA__
521452|DEGE|101|3|08/25/2024|12/13/2024|FA2024|3|A|||R
518444|ASH|109A|2|08/25/2024|12/13/2024|FA2024|2|A|||R
525615|ASH|203A|1|08/25/2024|12/13/2024|FA2024|2|A|||R
526061|OBRN|100B|2|08/25/2024|12/13/2024|FA2024|3|A|||R
