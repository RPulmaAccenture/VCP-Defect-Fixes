create or replace PACKAGE BODY        "XXNBTY_MSCEXT05_SAFETY_STK_PKG" 

--------------------------------------------------------------------------------------------
/*
Package Name: XXNBTY_MSCEXT05_SAFETY_STK_PKG
Author's Name: Mark Anthony Geamoga
Date written: 16-Jan-2015
RICEFW Object: EXT05
Description: This program validates records from staging table (xxnbty_msc_safety_stocks_st) to base table (MSC_SAFETY_STOCKS).
             It will generate Safety Stocks error report and send it to recipients.
             It will generate Safety Stocks report and send it to recipient(s) after data validation.
Program Style: 

Maintenance History: 

Date			Issue#		Name					Remarks	
-----------		------		-----------				------------------------------------------------
16-Jan-2015				 	Mark Anthony Geamoga	Initial Development
24-Feb-2015					Daniel Rodil			Updated procedure generate_email
													- case sensitive
													- calling of common vcp send email
													Modified commit to FND_CONCURRENT.AF_COMMIT;
27-Feb-2015					Erwin Ramos				Changed the main_pr to safety_stocks_main_pr
3-Mar-2015					Erwin Ramos				Changed SQLCODE to 2
6-Apr-2015		145			Erwin Ramos				Updated the column period_start_date. It will decode all previous date into the next Monday
*/
--------------------------------------------------------------------------------------------



IS
  --main procedure that will execute subprocedures for the generation of report
  PROCEDURE safety_stocks_main_pr (x_retcode             OUT VARCHAR2, 
                     x_errbuf              OUT VARCHAR2)
  IS
    l_request_id    NUMBER := fnd_global.conc_request_id;
    l_new_filename  VARCHAR2(200);
    l_old_filename  VARCHAR2(1000);
    l_subject       VARCHAR2(100);
    l_message       VARCHAR2(1000);
  BEGIN
    --define last updated by and created by
    g_last_updated_by := fnd_global.user_id;
    g_created_by      := fnd_global.user_id;
    
    FND_FILE.PUT_LINE(FND_FILE.LOG,'Validating records from the staging table.');  

    --validate data from Staging table
    validate_safety_stocks(x_retcode, x_errbuf);
    
    FND_FILE.PUT_LINE(FND_FILE.LOG,'Inserting records from staging to base table.'); 
    --insert data to Base table
    insert_safety_stocks(x_retcode, x_errbuf);
        
    --get new filename of the output file
    l_new_filename := 'XXNBTY_SAFETY_STOCKS_' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '.txt';    
        
    --subprocedure that will generate error output file.
    get_error_report(x_retcode
                     ,x_errbuf
                     ,l_request_id);
    
    IF l_request_id != 0 THEN                      
      --get output file after report generation.
      SELECT outfile_name
        INTO l_old_filename
        FROM fnd_concurrent_requests
       WHERE request_id = l_request_id;
        
        FND_FILE.PUT_LINE(FND_FILE.LOG,'Sending e-mail in progress...');
        
       l_subject := 'Safety Stocks Error Summary Report';
       l_message := 'Hi, \n\nAttached is the Safety Stocks Error Summary Report.\n\n*****This is an auto-generated e-mail. Please do not reply.*****';
        
        --compose and send email
        generate_email(x_retcode
                       ,x_errbuf
                       ,l_new_filename
                       ,l_old_filename
                       ,l_subject
                       ,l_message
                       ,'XXNBTY_MSC_SAFETY_STKS_ERR_EML');     
					   
    ELSE
      FND_FILE.PUT_LINE(FND_FILE.LOG,'No report to send. Sending e-mail skipped.');  
    END IF;
    
    l_request_id := 0;
    l_new_filename := NULL;
    l_old_filename := NULL;
    
    --new filename of the output file
    l_new_filename := 'Manual_Safety_Stocks_' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '.xls';

    --generate Safety Stocks report
    generate_report(x_retcode,
                    x_errbuf,
                    l_request_id);
    
    IF l_request_id != 0 THEN
      --get output file after report generation.
      SELECT REPLACE(outfile_name, 'o'||request_id||'.out', 'XXNBTY_MSC_SFTY_STKS_GEN_RPT_' || request_id || '_1.EXCEL')
        INTO l_old_filename
        FROM fnd_concurrent_requests
       WHERE request_id = l_request_id;
      
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Sending e-mail in progress...');
      
      l_subject := 'Safety Stocks Report';
      l_message := 'Hi, \n\nAttached is the Safety Stocks Report.\n\n*****This is an auto-generated e-mail. Please do not reply.*****';
      
      --compose and send email
      generate_email(x_retcode
                     ,x_errbuf
                     ,l_new_filename
                     ,l_old_filename
                     ,l_subject
                     ,l_message
                     ,'XXNBTY_MSC_SAFETY_STOCKS_EMAIL');
                            
    ELSE
      FND_FILE.PUT_LINE(FND_FILE.LOG,'No report to send. Sending e-mail skipped.');  
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      x_retcode := 2;
      x_errbuf := SQLERRM; 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error message : ' || x_errbuf);    
  END safety_stocks_main_pr;
  
   --subprocedure that will validate Safety Stocks from staging table
  PROCEDURE validate_safety_stocks (x_retcode             OUT VARCHAR2, 
                                    x_errbuf              OUT VARCHAR2)
  IS
    --retrieve all records with NULL value for required columns.
    CURSOR c_required
    IS SELECT  org
              ,item
              ,period_start_date
        FROM xxnbty_msc_safety_stocks_st
        WHERE item IS NULL
           OR org IS NULL
           OR period_start_date IS NULL
           OR (user_defined_safety_stocks IS NULL AND user_defined_dos IS NULL);
    
    --retrieve all records from staging with values for PERIOD_START_DATE column not in future.
    CURSOR c_date
    IS SELECT  org
              ,item
              ,period_start_date
          FROM xxnbty_msc_safety_stocks_st
          WHERE TRUNC(period_start_date) <= SYSDATE
            AND process_flag IS NULL;
  
    --retrieve all records from staging with value for both user_defined_safety_stocks and user_defined_dos columns
    CURSOR c_user_defined
    IS SELECT  org
              ,item
              ,period_start_date
          FROM xxnbty_msc_safety_stocks_st
          WHERE (user_defined_safety_stocks IS NOT NULL AND user_defined_dos IS NOT NULL)
            AND process_flag IS NULL;
  
    --retrieve all records that do not exist from MSC_PLAN_ORGANIZATIONS.
    CURSOR c_msc_plan
    IS SELECT  org
              ,item
              ,period_start_date
         FROM xxnbty_msc_safety_stocks_st
         WHERE org NOT IN (SELECT organization_code
                            FROM msc_trading_partners
                            WHERE partner_type = 3)                           
          AND process_flag IS NULL;
            
    --retrieve all records that do not exist from MSC_SYSTEM_ITEMS.
    CURSOR c_msc_items
    IS SELECT  stg.org
              ,stg.item
              ,stg.period_start_date
         FROM xxnbty_msc_safety_stocks_st stg
             ,msc_trading_partners mtp
         WHERE stg.org = mtp.organization_code
          AND NOT EXISTS (SELECT 1
                          FROM msc_system_items msi
                          WHERE msi.organization_id = mtp.sr_tp_id
                            AND msi.sr_instance_id = mtp.sr_instance_id
                            AND msi.item_name = stg.item)
          AND mtp.partner_type = 3
          AND stg.process_flag IS NULL;
  BEGIN
    --update the required columns(last_updated_by,created_by) in staging table with global values.
    UPDATE xxnbty_msc_safety_stocks_st 
      SET  last_update_date  = SYSDATE 
          ,last_updated_by   = g_last_updated_by 
          ,creation_date     = SYSDATE
          ,created_by        = g_created_by
		  ,period_start_date = decode (SIGN (period_start_date - sysdate), -1, next_day(sysdate,'MONDAY'), period_start_date) -- 06-Apr-2015: ERR: Added this line to resolved defect#145, it will decode the previous period_start_date to the next Monday  
      WHERE process_flag IS NULL; 
	     
    FND_CONCURRENT.AF_COMMIT;
  
    OPEN c_required;
    LOOP
    
      FETCH c_required BULK COLLECT INTO g_stg;
      
      FOR i IN 1..g_stg.COUNT
      LOOP
        UPDATE xxnbty_msc_safety_stocks_st 
          SET process_flag = '3'
             ,error_description = 'Missing value for required column(s).'
          WHERE item = g_stg(i).item
            AND org  = g_stg(i).org
            AND period_start_date = g_stg(i).period_start_date;
      END LOOP;
      
      EXIT WHEN c_required%NOTFOUND;
    END LOOP;
    CLOSE c_required;
    
    FND_CONCURRENT.AF_COMMIT;
    
    --delete contents of the array for re-use
    g_stg.DELETE();
    
    OPEN c_date;
    LOOP
    
      FETCH c_date BULK COLLECT INTO g_stg;
      
      FOR i IN 1..g_stg.COUNT
      LOOP
        UPDATE xxnbty_msc_safety_stocks_st 
          SET process_flag = '3'
             ,error_description = 'The value for PERIOD_START_DATE column is not in future.'
          WHERE item = g_stg(i).item
            AND org  = g_stg(i).org
            AND period_start_date = g_stg(i).period_start_date;
      END LOOP;
      
      EXIT WHEN c_date%NOTFOUND;
    END LOOP;
    CLOSE c_date;
    
    FND_CONCURRENT.AF_COMMIT;
    
    --delete contents of the array for re-use
    g_stg.DELETE();
  
    OPEN c_user_defined;
    LOOP
    
      FETCH c_user_defined BULK COLLECT INTO g_stg;
      
      FOR i IN 1..g_stg.COUNT
      LOOP
        UPDATE xxnbty_msc_safety_stocks_st 
          SET process_flag = '3'
             ,error_description = 'Only one from the USER_DEFINED_SAFETY_STOCKS and USER_DEFINED_DOS columns should have a value.'
          WHERE item = g_stg(i).item
            AND org  = g_stg(i).org
            AND period_start_date = g_stg(i).period_start_date;
      END LOOP;
      
      EXIT WHEN c_user_defined%NOTFOUND;
    END LOOP;
    CLOSE c_user_defined;
    
    FND_CONCURRENT.AF_COMMIT;
  
    --delete contents of the array for re-use
    g_stg.DELETE();
  
    OPEN c_msc_plan;
    LOOP
    
      FETCH c_msc_plan BULK COLLECT INTO g_stg;
      
      FOR i IN 1..g_stg.COUNT
      LOOP
        UPDATE xxnbty_msc_safety_stocks_st 
          SET process_flag = '3'
             ,error_description = 'Organization Code not exist in MSC_TRADING_PARTNERS.'
          WHERE item = g_stg(i).item
            AND org  = g_stg(i).org
            AND period_start_date = g_stg(i).period_start_date;
      END LOOP;
      
      EXIT WHEN c_msc_plan%NOTFOUND;
    END LOOP;
    CLOSE c_msc_plan;
    
    FND_CONCURRENT.AF_COMMIT;
    
    --delete contents of the array for re-use
    g_stg.DELETE();
    
    OPEN c_msc_items;
    LOOP
    
      FETCH c_msc_items BULK COLLECT INTO g_stg;
      
      FOR i IN 1..g_stg.COUNT
      LOOP
        UPDATE xxnbty_msc_safety_stocks_st 
          SET process_flag = '3'
             ,error_description = 'Item Code not exist in MSC_SYSTEM_ITEMS.'
          WHERE item = g_stg(i).item
            AND org  = g_stg(i).org
            AND period_start_date = g_stg(i).period_start_date;
      END LOOP;
      
      EXIT WHEN c_msc_items%NOTFOUND;
    END LOOP;
    CLOSE c_msc_items;
    
    FND_CONCURRENT.AF_COMMIT;
    
    --delete contents of the array for re-use
    g_stg.DELETE();
        
  EXCEPTION
    WHEN OTHERS THEN
      x_retcode := 2;
      x_errbuf := SQLERRM; 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error message : ' || x_errbuf); 
  END validate_safety_stocks;
  
  --subprocedure that will transfer Safety Stocks from staging to base table
  PROCEDURE insert_safety_stocks (x_retcode             OUT VARCHAR2, 
                                  x_errbuf              OUT VARCHAR2)
  IS
  
    base_deleted_flag    BOOLEAN := FALSE;
    
    --retrieve all records that exist from Safety Stocks Base table excluding those with error during data validation      
    CURSOR c_msc_stocks      
    IS SELECT  sfty.plan_id                            
             , sfty.organization_id                    
             , sfty.sr_instance_id                    
             , sfty.inventory_item_id               
             , stg.period_start_date                      --update PERIOD_START_DATE using the new value from the file loaded.        
             , sfty.safety_stock_quantity                    
             , sfty.UPDATED                                   
             , sfty.status                                    
             , sfty.refresh_number                           
             , SYSDATE                                    --update LAST_UPDATE_DATE to CURRENT DATE                  
             , stg.last_updated_by                        --update LAST_UPDATED_BY using the new value from the file loaded.
             , sfty.creation_date                 
             , sfty.created_by                       
             , sfty.last_update_login                       
             , sfty.request_id                           
             , sfty.program_id                             
             , sfty.program_update_date                     
             , sfty.program_application_id                 
             , sfty.target_safety_stock                        
             , sfty.project_id                             
             , sfty.task_id                                 
             , sfty.planning_group                      
             , stg.user_defined_safety_stocks             --update USER_DEFINED_SAFETY_STOCKS using the new value from the file loaded.  
             , stg.user_defined_dos                       --update USER_DEFINED_DOS using the new value from the file loaded.
             , sfty.target_days_of_supply                   
             , sfty.achieved_days_of_supply                 
             , sfty.unit_number                            
             , sfty.demand_var_ss_percent                    
             , sfty.mfg_ltvar_ss_percent                     
             , sfty.transit_ltvar_ss_percent                 
             , sfty.sup_ltvar_ss_percent                    
             , sfty.total_unpooled_safety_stock             
             , sfty.item_type_id                             
             , sfty.item_type_value                          
             , sfty.reserved_safety_stock_qty                
             , sfty.new_plan_id                              
             , sfty.simulation_set_id                        
             , sfty.new_plan_list                        
             , sfty.applied                                  
             , sfty.inventory_level  
      FROM msc_system_items msi
            ,msc_safety_stocks sfty
            ,xxnbty_msc_safety_stocks_st stg
            ,msc_trading_partners mtp
        WHERE msi.organization_id = sfty.organization_id
          AND msi.sr_instance_id = sfty.sr_instance_id
          AND msi.inventory_item_id = sfty.inventory_item_id
          AND msi.plan_id = sfty.plan_id
          AND sfty.organization_id = mtp.sr_tp_id
          AND sfty.sr_instance_id = mtp.sr_instance_id
          AND TRUNC(sfty.period_start_date) = TRUNC(stg.period_start_date)
          AND stg.org = mtp.organization_code
          AND stg.item = msi.item_name
          AND stg.process_flag IS NULL
          AND sfty.plan_id = -1;
          
    --retrieve all processed records in staging table that were updated in the base table.
    CURSOR c_stg
    IS SELECT  mtp.organization_code, msi.item_name, TRUNC(sfty.period_start_date)
          FROM msc_system_items msi
            ,msc_safety_stocks sfty
            ,xxnbty_msc_safety_stocks_st stg
            ,msc_trading_partners mtp
        WHERE msi.organization_id = sfty.organization_id
          AND msi.sr_instance_id = sfty.sr_instance_id
          AND msi.inventory_item_id = sfty.inventory_item_id
          AND msi.plan_id = sfty.plan_id
          AND sfty.organization_id = mtp.sr_tp_id
          AND sfty.sr_instance_id = mtp.sr_instance_id
          AND TRUNC(sfty.period_start_date) = TRUNC(stg.period_start_date)
          AND stg.org = mtp.organization_code
          AND stg.item = msi.item_name
          AND stg.process_flag IS NULL
          AND sfty.plan_id = -1;
            
    --retrieve all remaining valid and new records in the staging table.
    CURSOR c_stg_valid
    IS SELECT    msi.plan_id
          ,      mtp.sr_tp_id
          ,      msi.sr_instance_id
          ,      msi.inventory_item_id
          ,      TRUNC(stg.period_start_date)
          ,      0
          ,      SYSDATE
          ,      stg.last_updated_by
          ,      SYSDATE
          ,      stg.created_by
          ,      stg.user_defined_safety_stocks
          ,      stg.user_defined_dos
        FROM xxnbty_msc_safety_stocks_st stg
            ,msc_system_items msi
            ,msc_trading_partners mtp
       WHERE stg.org = mtp.organization_code
        AND stg.item = msi.item_name
        AND stg.process_flag IS NULL
        AND msi.organization_id = mtp.sr_tp_id
        AND msi.sr_instance_id = mtp.sr_instance_id
        AND msi.plan_id = -1;
  BEGIN
    OPEN c_msc_stocks;
    LOOP
      --put all records that exist from staging and base tables in an array. 
      FETCH c_msc_stocks BULK COLLECT INTO g_stocks;
   
      IF g_stocks.COUNT >= 1 THEN 
        --delete all records from base table.
        EXECUTE IMMEDIATE 'DELETE FROM msc_safety_stocks WHERE plan_id = -1'; 
        base_deleted_flag := TRUE;
      END IF;
      
      --insert back all records that exist from staging and base tables with the updated required columns.
      FORALL i IN 1..g_stocks.COUNT
      INSERT INTO msc_safety_stocks VALUES g_stocks(i);
      
      EXIT WHEN c_msc_stocks%NOTFOUND;
    END LOOP;
    CLOSE c_msc_stocks;
  
    FND_CONCURRENT.AF_COMMIT;
    
    --delete contents of the array for re-use
    g_stocks.DELETE();
    
    OPEN c_stg;
    LOOP
      
      FETCH c_stg BULK COLLECT INTO g_stg;
   
      FORALL i IN 1..g_stg.COUNT
      --update the process_flag of processed records in the staging table.
      UPDATE xxnbty_msc_safety_stocks_st
         SET process_flag = '5'
            ,error_description = NULL
       WHERE (org||item||period_start_date) IN (g_stg(i).org||g_stg(i).item||g_stg(i).period_start_date);
  --    WHERE org IN (g_stg(i).org)  
    --    AND item IN (g_stg(i).item)
      --  AND period_start_date IN (g_stg(i).period_start_date);
      
      EXIT WHEN c_stg%NOTFOUND;
    END LOOP;
    CLOSE c_stg;
    
    FND_CONCURRENT.AF_COMMIT;
  
    --delete contents of the array for re-use
    g_stg.DELETE();
    
    OPEN c_stg_valid;
    LOOP
    
      FETCH c_stg_valid BULK COLLECT INTO g_sfty;
   
      IF g_sfty.COUNT >= 1 AND NOT base_deleted_flag THEN 
        --delete all records from base table.
        EXECUTE IMMEDIATE 'DELETE FROM msc_safety_stocks WHERE plan_id = -1'; 
      END IF;
   
      --insert valid records from staging to base table.
      FORALL i IN 1..g_sfty.COUNT
      INSERT INTO msc_safety_stocks (   plan_id
                                      , organization_id
                                      , sr_instance_id
                                      , inventory_item_id
                                      , period_start_date
                                      , safety_stock_quantity
                                      , last_update_date
                                      , last_updated_by
                                      , creation_date
                                      , created_by
                                      , user_defined_safety_stocks
                                      , user_defined_dos
                                    )
              VALUES(   g_sfty(i).plan_id
                      , g_sfty(i).organization_id
                      , g_sfty(i).sr_instance_id
                      , g_sfty(i).inventory_item_id
                      , g_sfty(i).period_start_date
                      , g_sfty(i).safety_stock_quantity
                      , g_sfty(i).last_update_date
                      , g_sfty(i).last_updated_by
                      , g_sfty(i).creation_date
                      , g_sfty(i).created_by
                      , g_sfty(i).user_defined_safety_stocks
                      , g_sfty(i).user_defined_dos);
              
        --update the process_flag of the remaining valid records in the staging table.
        UPDATE xxnbty_msc_safety_stocks_st
           SET process_flag = '5'
              ,error_description = NULL
         WHERE process_flag IS NULL;
      
      EXIT WHEN c_stg_valid%NOTFOUND;
    END LOOP;
    CLOSE c_stg_valid;
    
    FND_CONCURRENT.AF_COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      x_retcode := 2;
      x_errbuf := SQLERRM; 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error message : ' || x_errbuf); 
  END insert_safety_stocks;
  
  --subprocedure that will generate error output file.
  PROCEDURE generate_error_report (x_retcode             OUT VARCHAR2, 
                                   x_errbuf              OUT VARCHAR2
                                   )
  IS
    l_max_length    NUMBER;
    l_side_length   NUMBER;
    
    l_report_title  VARCHAR2(200);
    l_report_footer VARCHAR2(200);
    l_title         VARCHAR2(50);
    l_header        VARCHAR2(1000);
    
    TYPE err_type   IS RECORD (error_msg VARCHAR2(4000),
                               ctr       NUMBER);    
    TYPE err_rec_type    IS RECORD ( p_item     xxnbty_msc_safety_stocks_st.item%TYPE
                               ,p_org      xxnbty_msc_safety_stocks_st.org%TYPE
                               ,p_date     xxnbty_msc_safety_stocks_st.period_start_date%TYPE
                               ,p_error    xxnbty_msc_safety_stocks_st.error_description%TYPE);
    TYPE err_tab_type        IS TABLE OF err_type; 
    TYPE err_rec_tab_type    IS TABLE OF err_rec_type; 

    v_err           err_tab_type;
    v_err_rec       err_rec_tab_type;
    
    --retrieve summary of errored records in staging table.
    CURSOR c_errored_rec_summary
    IS SELECT error_description, count(*)
        FROM xxnbty_msc_safety_stocks_st
        WHERE process_flag = 3
        GROUP BY error_description;
           
    --retrieve all errored records in staging table.
    CURSOR c_errored_rec
    IS SELECT item, org, period_start_date, error_description
        FROM xxnbty_msc_safety_stocks_st
        WHERE process_flag = 3
        ORDER BY error_description;
  
  BEGIN
  
    SELECT NVL(MAX(LENGTH(error_description)), 0) + 16 maximum_length
      INTO l_max_length
      FROM xxnbty_msc_safety_stocks_st
     WHERE process_flag = 3;
        
    --set default width of report to 100
    IF NVL(l_max_length,99) < 100 THEN
      l_max_length := 100;
    END IF;
    
    l_title := 'SUMMARY REPORT FOR SAFETY STOCKS PROGRAM';
    
    l_side_length := TRUNC((l_max_length - LENGTH(l_title)) / 2);
    
    --display header of the output file
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'  ' || RPAD('XXNBTY_SAFETY_STOCKS_' || TO_CHAR(SYSDATE, 'YYYYMMDD'), l_max_length - 17, ' ') || TO_CHAR(SYSDATE, 'DD-MON-YYYY HH:MI:SS AM') || '  ');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,LPAD(' ', l_side_length + 4, ' ') || l_title );
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'');
    
    OPEN c_errored_rec_summary;    
    LOOP
      FETCH c_errored_rec_summary BULK COLLECT INTO v_err;
      
        l_header := 'MSC_SAFETY_STOCKS';
        l_side_length := TRUNC((l_max_length - LENGTH(l_header)) / 2);
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'');
        
        --display header
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'  ' || RPAD(LPAD(l_header, l_side_length + LENGTH(l_header) + 3, '*'), l_max_length + 6, '*')  || '  ');
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'');
        
        IF v_err.COUNT = 0 THEN
          FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'     ALL RECORDS FOR STAGING TABLE OF SAFETY STOCKS ARE VALID.');
        ELSE          
          --display column header
          FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'     Error Count     Error Message');
          FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'     -----------     -------------');
        END IF;
        
        FOR ii IN 1..v_err.COUNT
        LOOP
            FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'     ' || RPAD(TO_CHAR(v_err(ii).ctr, 'fm999,999,999,999,999'), 16, ' ') || v_err(ii).error_msg);
        END LOOP;
        EXIT WHEN c_errored_rec_summary%NOTFOUND;
    END LOOP;
    CLOSE c_errored_rec_summary;
    
    OPEN c_errored_rec;    
    LOOP
      FETCH c_errored_rec BULK COLLECT INTO v_err_rec;
      
        l_title := 'DETAILED REPORT FOR SAFETY STOCKS PROGRAM';
      
        l_side_length := TRUNC((l_max_length - LENGTH(l_title)) / 2);
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'');
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'');
        
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,LPAD(' ', l_side_length + 4, ' ') || l_title );
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'');
        
        IF v_err_rec.COUNT = 0 THEN
          FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'     ALL RECORDS FOR STAGING TABLE OF SAFETY STOCKS ARE VALID.');
        ELSE          
          --display column header
          FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'       ITEM           ORG       Period Start Date   Error Description');
          FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'     ----------     --------    -----------------   -----------------');
                                                                                      
        END IF;
        
        FOR ii IN 1..v_err_rec.COUNT
        LOOP
          FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'     ' || v_err_rec(ii).p_item || '      ' || v_err_rec(ii).p_org || '     ' || v_err_rec(ii).p_date || '           ' || v_err_rec(ii).p_error);
        END LOOP;
        EXIT WHEN c_errored_rec%NOTFOUND;
    END LOOP;
    CLOSE c_errored_rec;
    
    --get report footer
    l_report_footer := 'END OF REPORT';
    
    l_side_length := TRUNC((l_max_length - LENGTH(l_report_footer)) / 2);
    
    --display footer of the output file
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'  ' || RPAD(LPAD(l_report_footer, l_side_length + LENGTH(l_report_footer), '*'), l_max_length + 6, '*') || '  ');
  
  EXCEPTION
    WHEN OTHERS THEN
      x_retcode := 2;
      x_errbuf := SQLERRM; 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error message : ' || x_errbuf);
  END generate_error_report;
  
  --subprocedure that will...
  PROCEDURE get_error_report (x_retcode             OUT VARCHAR2, 
                              x_errbuf              OUT VARCHAR2,
                              x_request_id         OUT NUMBER)
  IS
    l_request_id  NUMBER;
    l_flag         BOOLEAN;
    l_reqphase     VARCHAR2(50);
    l_reqstatus    VARCHAR2(50);
    l_reqdevphase  VARCHAR2(50);
    l_reqdevstatus VARCHAR2(50);
    l_reqmessage   VARCHAR2(50);
  BEGIN
  
    l_request_id := FND_REQUEST.SUBMIT_REQUEST(application  => 'XXNBTY'
                                               ,program      => 'XXNBTY_MSC_SFTY_STKS_ERROR_RPT'
                                               ,start_time   => TO_CHAR(SYSDATE,'DD-MON-YYYY HH:MI:SS')
                                               ,sub_request  => FALSE
                                               );
    FND_CONCURRENT.AF_COMMIT;                
    
    --wait for the for the Safety Stocks error report to be generated before sending email
    l_flag := FND_CONCURRENT.WAIT_FOR_REQUEST(request_id => l_request_id,
                                              interval => 30,
                                              max_wait => '',
                                              phase => l_reqphase,
                                              status => l_reqstatus,
                                              dev_phase => l_reqdevphase,
                                              dev_status => l_reqdevstatus,
                                              MESSAGE => l_reqmessage);
    FND_CONCURRENT.AF_COMMIT;
    
    --check for the report completion
    IF (l_reqdevphase = 'COMPLETE' AND l_reqdevstatus = 'NORMAL') THEN 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error Report successfully generated.'); 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Request ID of XXNBTY Safety Stocks Generate Error Report is ' || l_request_id); 
      x_request_id := l_request_id;
    ELSE
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Generating error report for Safety Stocks failed.');  
      x_request_id := 0;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      x_retcode := 2;
      x_errbuf := SQLERRM; 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error message : ' || x_errbuf);
  END get_error_report;

  --subprocedure that will generate Safety Stocks report
  PROCEDURE generate_report (x_retcode             OUT VARCHAR2, 
                             x_errbuf              OUT VARCHAR2,
                             x_request_id         OUT NUMBER)
  IS
    l_request_id  NUMBER;
    l_flag1        BOOLEAN;
    l_flag2        BOOLEAN;
    l_reqphase     VARCHAR2(50);
    l_reqstatus    VARCHAR2(50);
    l_reqdevphase  VARCHAR2(50);
    l_reqdevstatus VARCHAR2(50);
    l_reqmessage   VARCHAR2(50);
  BEGIN
    
    --create layout for Safety Stock Report
    l_flag1 := FND_REQUEST.ADD_LAYOUT ('XXNBTY',
                                      'XXNBTY_MSC_SFTY_STKS_GEN_RPT',
                                      'En',
                                      'US',
                                      'EXCEL' );
    IF (l_flag1) THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'The layout has been submitted');
    ELSE
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'The layout has not been submitted');
    END IF;
    
    l_request_id := FND_REQUEST.SUBMIT_REQUEST(application  => 'XXNBTY'
                                               ,program      => 'XXNBTY_MSC_SFTY_STKS_GEN_RPT'
                                               ,start_time   => TO_CHAR(SYSDATE,'DD-MON-YYYY HH:MI:SS')
                                               ,sub_request  => FALSE
                                               );
    FND_CONCURRENT.AF_COMMIT;                
    
    --wait for the for the Safety Stocks report to be generated before sending email
    l_flag2 := FND_CONCURRENT.WAIT_FOR_REQUEST(request_id => l_request_id,
                                              interval => 30,
                                              max_wait => '',
                                              phase => l_reqphase,
                                              status => l_reqstatus,
                                              dev_phase => l_reqdevphase,
                                              dev_status => l_reqdevstatus,
                                              MESSAGE => l_reqmessage);
    FND_CONCURRENT.AF_COMMIT;
    
    --check for the report completion
    IF (l_reqdevphase = 'COMPLETE' AND l_reqdevstatus = 'NORMAL') THEN 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Report successfully generated.'); 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Request ID of XXNBTY Safety Stocks Generate Report is ' || l_request_id); 
      x_request_id := l_request_id;
    ELSE
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error in generating report for Safety Stocks.');  
      x_request_id := 0;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      x_retcode := 2;
      x_errbuf := SQLERRM; 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error message : ' || x_errbuf);
  END generate_report;
  
  --subprocedure that will send Safety Stocks report to recipient(s) from the lookups
  PROCEDURE generate_email (x_retcode   OUT VARCHAR2, 
                            x_errbuf    OUT VARCHAR2,
                            p_new_filename VARCHAR2,
                            p_old_filename VARCHAR2,
                            p_subject      VARCHAR2,
                            p_message      VARCHAR2,
                            p_lookup_name  VARCHAR2)
  IS
    l_request_id    NUMBER;
    lp_email_to     VARCHAR2(1000);
    lp_email_to_cc  VARCHAR2(1000);
    lp_email_to_bcc VARCHAR2(1000);
    
    CURSOR c_lookup_email_ad --lookup for direct recipient(s)
    IS
       SELECT meaning
        FROM fnd_lookup_values
       WHERE lookup_type = p_lookup_name
         AND enabled_flag = 'Y'
         AND UPPER(tag) = 'TO'  -- drodil 24-feb-2015 added upper
         AND SYSDATE BETWEEN start_date_active and nvl(end_date_active,SYSDATE);
         
    CURSOR c_lookup_email_cc_ad --lookup for cc recipient(s)
    IS
       SELECT meaning
        FROM fnd_lookup_values
       WHERE lookup_type = p_lookup_name
         AND enabled_flag = 'Y'
         AND UPPER(tag) = 'CC' -- drodil 24-feb-2015 added upper
         AND SYSDATE BETWEEN start_date_active and nvl(end_date_active,SYSDATE);
         
    CURSOR c_lookup_email_bcc_ad --lookup for bcc recipient(s)
    IS
       SELECT meaning
        FROM fnd_lookup_values
       WHERE lookup_type = p_lookup_name
         AND enabled_flag = 'Y'
         AND UPPER(tag) = 'BCC'  -- drodil 24-feb-2015 added upper
         AND SYSDATE BETWEEN start_date_active and nvl(end_date_active,SYSDATE);     
  BEGIN
  
    --check all direct recipients in lookup 
    FOR rec_send IN c_lookup_email_ad
    LOOP
      lp_email_to := LTRIM(lp_email_to||','||rec_send.meaning,',');
    END LOOP;
    
    --check all cc recipients in lookup 
    FOR rec_send_cc IN c_lookup_email_cc_ad
    LOOP
      lp_email_to_cc := LTRIM(lp_email_to_cc||','||rec_send_cc.meaning,',');
    END LOOP;
    
    --check all bcc recipients in lookup 
    FOR rec_send_bcc IN c_lookup_email_bcc_ad
    LOOP
      lp_email_to_bcc := LTRIM(lp_email_to_bcc||','||rec_send_bcc.meaning,',');
    END LOOP;
    
    FND_FILE.PUT_LINE(FND_FILE.LOG,'New Filename : ' || p_new_filename); 
    FND_FILE.PUT_LINE(FND_FILE.LOG,'Old Filename : ' || p_old_filename);
    FND_FILE.PUT_LINE(FND_FILE.LOG,'Direct Recipient : ' || lp_email_to);
    FND_FILE.PUT_LINE(FND_FILE.LOG,'Carbon Copy Recipient : ' || lp_email_to_cc);
    FND_FILE.PUT_LINE(FND_FILE.LOG,'Blind Carbon Copy Recipient : ' || lp_email_to_bcc);
    FND_FILE.PUT_LINE(FND_FILE.LOG,'Email Subject : ' || p_subject);
    FND_FILE.PUT_LINE(FND_FILE.LOG,'Email Content : ' || p_message);
    
    IF lp_email_to_bcc IS NOT NULL AND lp_email_to_cc IS NULL THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Cannot proceed in sending email due to BCC recipient contains a value and CC recipient is missing.');
    ELSE --send email if recipient is valid.
    --get request id generated after running concurrent program
    l_request_id := FND_REQUEST.SUBMIT_REQUEST(application  => 'XXNBTY'
                                               ,program      => 'XXNBTY_VCP_SEND_EMAIL_LOG'  -- drodil 24-feb-2015 modified to use the commmon sending of email 
                                               ,start_time   => TO_CHAR(SYSDATE,'DD-MON-YYYY HH:MI:SS')
                                               ,sub_request  => FALSE
                                               ,argument1    => p_new_filename
                                               ,argument2    => p_old_filename
                                               ,argument3    => lp_email_to
                                               ,argument4    => lp_email_to_cc
                                               ,argument5    => lp_email_to_bcc
                                               ,argument6    => p_subject
                                               ,argument7    => p_message
                                               );
    FND_CONCURRENT.AF_COMMIT;
    END IF; 
    
    FND_FILE.PUT_LINE(FND_FILE.LOG,'Request ID of XXNBTY Safety Stocks Send Email Log : ' || l_request_id);  
                                               
    IF l_request_id != 0 THEN 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Sending successful.');     
    ELSE
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error in sending email.'); 
    END IF;

  EXCEPTION
    WHEN OTHERS THEN
      x_retcode := 2;
      x_errbuf := SQLERRM; 
      FND_FILE.PUT_LINE(FND_FILE.LOG,'Error message : ' || x_errbuf);
  END generate_email;
  
END XXNBTY_MSCEXT05_SAFETY_STK_PKG;
/
show errors;
