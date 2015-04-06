--------------------------------------------------------------------------------------------------------
/*
	Table Name: xxnbty_catalog_staging_tbl																		
	Author's Name: Albert Flores																			
	Date written: 23-Mar-2015																							
	RICEFW Object: REP01																								
	Description: Index for for xxnbty_catalog_staging_tbl REP01-Multilevel Pegging Report.																
	Program Style: 																									
																													
	Maintenance History:																							
																													
	Date			Issue#		Name						Remarks																
	-----------		------		-----------					------------------------------------------------					
	26-Mar-2015				 	Albert Flores				Initial Development

*/			
--------------------------------------------------------------------------------------------------------

	CREATE UNIQUE INDEX
		xxnbty_catalog_staging_tbl_U1
	ON
	   xxnbty_catalog_staging_tbl
	(    item_name
		,organization_id
	 );
	   
	   