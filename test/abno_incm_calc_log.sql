delete from cmssdata.abno_incm_calc_log where abno_incm_calc_btch like '0%';
INSERT INTO CMSSDATA.ABNO_INCM_CALC_LOG VALUES ('000001', '20160401', '20170401', '1', '11', '3', '2810,2310,1110,1540', '3', 0, '00000000', current_timestamp(0), 'user1', '0');
INSERT INTO CMSSDATA.ABNO_INCM_CALC_LOG VALUES ('000002', '20160401', '20170401', '1', '1', '1', 'tmp_invst_1_000002.txt', '0', 0, '00000000', current_timestamp(0), 'user1', '0');
INSERT INTO CMSSDATA.ABNO_INCM_CALC_LOG VALUES ('000003', '20160401', '20170401', '2', 'tmp_obj_000003.txt', '2', 'tmp_invst_2_000003.txt', '1', 0.002, '00000000', current_timestamp(0), 'user1', '0');
INSERT INTO CMSSDATA.ABNO_INCM_CALC_LOG VALUES ('000004', '20160401', '20170401', '2', 'upload_obj_000004.txt', '2', 'upload_invst_2_000004.txt', '0', 0, '00000000', current_timestamp(0), 'user1', '0');
select * from cmssdata.abno_incm_calc_log;
