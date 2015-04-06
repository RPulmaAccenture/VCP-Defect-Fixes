CREATE TABLE xxnbty.xxnbty_catalog_staging_tbl
(
	 inventory_item_id		NUMBER
	,item_name				VARCHAR2(250)
	,organization_id		NUMBER
	,icc					VARCHAR2(40)
	,blend					VARCHAR2(40)
	,catalog_group			VARCHAR2(40)
);
--[PUBLIC SYNONYM xxnbty_catalog_staging_tbl]
CREATE OR REPLACE PUBLIC SYNONYM xxnbty_catalog_staging_tbl for xxnbty.xxnbty_catalog_staging_tbl;