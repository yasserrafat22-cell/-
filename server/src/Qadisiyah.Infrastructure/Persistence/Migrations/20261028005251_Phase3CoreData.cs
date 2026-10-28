using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Qadisiyah.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Phase3CoreData : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "app_settings",
                columns: table => new
                {
                    key = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    value = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_app_settings", x => x.key);
                });

            migrationBuilder.CreateTable(
                name: "lookup_items",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    category = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    code = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    name_ar = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    name_en = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    semantic = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                    applies_to = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    is_system = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_lookup_items", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "materials",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    code = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    name_ar = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    name_en = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_materials", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "representatives",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    phone = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    user_id = table.Column<Guid>(type: "uuid", nullable: true),
                    is_active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_representatives", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "units",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    code = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    name_ar = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    factor_to_kg = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_units", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "grades",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    material_id = table.Column<Guid>(type: "uuid", nullable: false),
                    code = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    normalized_code = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    description = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    is_active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_grades", x => x.id);
                    table.ForeignKey(
                        name: "fk_grades_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "material_aliases",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    material_id = table.Column<Guid>(type: "uuid", nullable: false),
                    alias = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    normalized = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_material_aliases", x => x.id);
                    table.ForeignKey(
                        name: "fk_material_aliases_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "parties",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    normalized_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    is_customer = table.Column<bool>(type: "boolean", nullable: false),
                    is_supplier = table.Column<bool>(type: "boolean", nullable: false),
                    customer_activity_id = table.Column<Guid>(type: "uuid", nullable: true),
                    supplier_activity_id = table.Column<Guid>(type: "uuid", nullable: true),
                    representative_id = table.Column<Guid>(type: "uuid", nullable: true),
                    email = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    notes = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    country_code = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    governorate_id = table.Column<Guid>(type: "uuid", nullable: true),
                    region = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    address_line = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    latitude = table.Column<double>(type: "double precision", nullable: true),
                    longitude = table.Column<double>(type: "double precision", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_parties", x => x.id);
                    table.ForeignKey(
                        name: "fk_parties_lookup_items_customer_activity_id",
                        column: x => x.customer_activity_id,
                        principalTable: "lookup_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_parties_lookup_items_governorate_id",
                        column: x => x.governorate_id,
                        principalTable: "lookup_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_parties_lookup_items_supplier_activity_id",
                        column: x => x.supplier_activity_id,
                        principalTable: "lookup_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_parties_representatives_representative_id",
                        column: x => x.representative_id,
                        principalTable: "representatives",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "customer_interests",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    party_id = table.Column<Guid>(type: "uuid", nullable: false),
                    material_id = table.Column<Guid>(type: "uuid", nullable: false),
                    grade_id = table.Column<Guid>(type: "uuid", nullable: true),
                    monthly_quantity = table.Column<decimal>(type: "numeric(18,3)", precision: 18, scale: 3, nullable: true),
                    unit_id = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_customer_interests", x => x.id);
                    table.ForeignKey(
                        name: "fk_customer_interests_grades_grade_id",
                        column: x => x.grade_id,
                        principalTable: "grades",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_customer_interests_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_customer_interests_parties_party_id",
                        column: x => x.party_id,
                        principalTable: "parties",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_customer_interests_units_unit_id",
                        column: x => x.unit_id,
                        principalTable: "units",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "interactions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    party_id = table.Column<Guid>(type: "uuid", nullable: false),
                    channel = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    outcome_id = table.Column<Guid>(type: "uuid", nullable: false),
                    occurred_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    notes = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    next_follow_up_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    remind = table.Column<bool>(type: "boolean", nullable: false),
                    follow_up_done = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_interactions", x => x.id);
                    table.ForeignKey(
                        name: "fk_interactions_lookup_items_outcome_id",
                        column: x => x.outcome_id,
                        principalTable: "lookup_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_interactions_parties_party_id",
                        column: x => x.party_id,
                        principalTable: "parties",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "orders",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    customer_id = table.Column<Guid>(type: "uuid", nullable: false),
                    order_date = table.Column<DateOnly>(type: "date", nullable: false),
                    stage = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    on_hold = table.Column<bool>(type: "boolean", nullable: false),
                    representative_id = table.Column<Guid>(type: "uuid", nullable: true),
                    notes = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_orders", x => x.id);
                    table.ForeignKey(
                        name: "fk_orders_parties_customer_id",
                        column: x => x.customer_id,
                        principalTable: "parties",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_orders_representatives_representative_id",
                        column: x => x.representative_id,
                        principalTable: "representatives",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "party_phones",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    party_id = table.Column<Guid>(type: "uuid", nullable: false),
                    e164 = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    label = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    is_primary = table.Column<bool>(type: "boolean", nullable: false),
                    whats_app_e164 = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_party_phones", x => x.id);
                    table.ForeignKey(
                        name: "fk_party_phones_parties_party_id",
                        column: x => x.party_id,
                        principalTable: "parties",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "supplier_products",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    party_id = table.Column<Guid>(type: "uuid", nullable: false),
                    material_id = table.Column<Guid>(type: "uuid", nullable: false),
                    grade_id = table.Column<Guid>(type: "uuid", nullable: true),
                    notes = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    is_active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_supplier_products", x => x.id);
                    table.ForeignKey(
                        name: "fk_supplier_products_grades_grade_id",
                        column: x => x.grade_id,
                        principalTable: "grades",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_supplier_products_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_supplier_products_parties_party_id",
                        column: x => x.party_id,
                        principalTable: "parties",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "supplies",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    supplier_id = table.Column<Guid>(type: "uuid", nullable: false),
                    supply_date = table.Column<DateOnly>(type: "date", nullable: false),
                    status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    notes = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_supplies", x => x.id);
                    table.ForeignKey(
                        name: "fk_supplies_parties_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "parties",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "order_lines",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    order_id = table.Column<Guid>(type: "uuid", nullable: false),
                    line_no = table.Column<int>(type: "integer", nullable: false),
                    material_id = table.Column<Guid>(type: "uuid", nullable: false),
                    grade_id = table.Column<Guid>(type: "uuid", nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(18,3)", precision: 18, scale: 3, nullable: false),
                    unit_id = table.Column<Guid>(type: "uuid", nullable: false),
                    quantity_kg = table.Column<decimal>(type: "numeric(18,3)", precision: 18, scale: 3, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_order_lines", x => x.id);
                    table.ForeignKey(
                        name: "fk_order_lines_grades_grade_id",
                        column: x => x.grade_id,
                        principalTable: "grades",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_order_lines_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_order_lines_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_order_lines_units_unit_id",
                        column: x => x.unit_id,
                        principalTable: "units",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "order_stage_changes",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    order_id = table.Column<Guid>(type: "uuid", nullable: false),
                    from_stage = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true),
                    to_stage = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    by = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_order_stage_changes", x => x.id);
                    table.ForeignKey(
                        name: "fk_order_stage_changes_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "price_quotes",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    supplier_product_id = table.Column<Guid>(type: "uuid", nullable: false),
                    price = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    unit_id = table.Column<Guid>(type: "uuid", nullable: false),
                    quote_date = table.Column<DateOnly>(type: "date", nullable: false),
                    valid_until = table.Column<DateOnly>(type: "date", nullable: true),
                    transport_note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    tax_note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    notes = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_price_quotes", x => x.id);
                    table.ForeignKey(
                        name: "fk_price_quotes_supplier_products_supplier_product_id",
                        column: x => x.supplier_product_id,
                        principalTable: "supplier_products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_price_quotes_units_unit_id",
                        column: x => x.unit_id,
                        principalTable: "units",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "supply_lines",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    supply_id = table.Column<Guid>(type: "uuid", nullable: false),
                    line_no = table.Column<int>(type: "integer", nullable: false),
                    material_id = table.Column<Guid>(type: "uuid", nullable: false),
                    grade_id = table.Column<Guid>(type: "uuid", nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(18,3)", precision: 18, scale: 3, nullable: false),
                    unit_id = table.Column<Guid>(type: "uuid", nullable: false),
                    quantity_kg = table.Column<decimal>(type: "numeric(18,3)", precision: 18, scale: 3, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_supply_lines", x => x.id);
                    table.ForeignKey(
                        name: "fk_supply_lines_grades_grade_id",
                        column: x => x.grade_id,
                        principalTable: "grades",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_supply_lines_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_supply_lines_supplies_supply_id",
                        column: x => x.supply_id,
                        principalTable: "supplies",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_supply_lines_units_unit_id",
                        column: x => x.unit_id,
                        principalTable: "units",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_customer_interests_grade_id",
                table: "customer_interests",
                column: "grade_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_interests_material_id_grade_id",
                table: "customer_interests",
                columns: new[] { "material_id", "grade_id" });

            migrationBuilder.CreateIndex(
                name: "ix_customer_interests_party_id",
                table: "customer_interests",
                column: "party_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_interests_unit_id",
                table: "customer_interests",
                column: "unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_grades_material_id_normalized_code",
                table: "grades",
                columns: new[] { "material_id", "normalized_code" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_interactions_next_follow_up_at",
                table: "interactions",
                column: "next_follow_up_at",
                filter: "follow_up_done = false");

            migrationBuilder.CreateIndex(
                name: "ix_interactions_outcome_id",
                table: "interactions",
                column: "outcome_id");

            migrationBuilder.CreateIndex(
                name: "ix_interactions_party_id_occurred_at",
                table: "interactions",
                columns: new[] { "party_id", "occurred_at" });

            migrationBuilder.CreateIndex(
                name: "ix_interactions_updated_at",
                table: "interactions",
                column: "updated_at");

            migrationBuilder.CreateIndex(
                name: "ix_lookup_items_category_code",
                table: "lookup_items",
                columns: new[] { "category", "code" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_material_aliases_material_id",
                table: "material_aliases",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_material_aliases_normalized",
                table: "material_aliases",
                column: "normalized");

            migrationBuilder.CreateIndex(
                name: "ix_materials_code",
                table: "materials",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_order_lines_grade_id",
                table: "order_lines",
                column: "grade_id");

            migrationBuilder.CreateIndex(
                name: "ix_order_lines_material_id",
                table: "order_lines",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_order_lines_order_id",
                table: "order_lines",
                column: "order_id");

            migrationBuilder.CreateIndex(
                name: "ix_order_lines_unit_id",
                table: "order_lines",
                column: "unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_order_stage_changes_order_id",
                table: "order_stage_changes",
                column: "order_id");

            migrationBuilder.CreateIndex(
                name: "ix_orders_customer_id_order_date",
                table: "orders",
                columns: new[] { "customer_id", "order_date" });

            migrationBuilder.CreateIndex(
                name: "ix_orders_representative_id",
                table: "orders",
                column: "representative_id");

            migrationBuilder.CreateIndex(
                name: "ix_orders_updated_at",
                table: "orders",
                column: "updated_at");

            migrationBuilder.CreateIndex(
                name: "ix_parties_customer_activity_id",
                table: "parties",
                column: "customer_activity_id");

            migrationBuilder.CreateIndex(
                name: "ix_parties_governorate_id",
                table: "parties",
                column: "governorate_id");

            migrationBuilder.CreateIndex(
                name: "ix_parties_normalized_name",
                table: "parties",
                column: "normalized_name");

            migrationBuilder.CreateIndex(
                name: "ix_parties_representative_id",
                table: "parties",
                column: "representative_id");

            migrationBuilder.CreateIndex(
                name: "ix_parties_supplier_activity_id",
                table: "parties",
                column: "supplier_activity_id");

            migrationBuilder.CreateIndex(
                name: "ix_parties_updated_at",
                table: "parties",
                column: "updated_at");

            migrationBuilder.CreateIndex(
                name: "ix_party_phones_e164",
                table: "party_phones",
                column: "e164");

            migrationBuilder.CreateIndex(
                name: "ix_party_phones_party_id",
                table: "party_phones",
                column: "party_id");

            migrationBuilder.CreateIndex(
                name: "ix_price_quotes_supplier_product_id_quote_date",
                table: "price_quotes",
                columns: new[] { "supplier_product_id", "quote_date" });

            migrationBuilder.CreateIndex(
                name: "ix_price_quotes_unit_id",
                table: "price_quotes",
                column: "unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_representatives_user_id",
                table: "representatives",
                column: "user_id",
                unique: true,
                filter: "user_id IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ix_supplier_products_grade_id",
                table: "supplier_products",
                column: "grade_id");

            migrationBuilder.CreateIndex(
                name: "ix_supplier_products_material_id_grade_id",
                table: "supplier_products",
                columns: new[] { "material_id", "grade_id" });

            migrationBuilder.CreateIndex(
                name: "ix_supplier_products_party_id",
                table: "supplier_products",
                column: "party_id");

            migrationBuilder.CreateIndex(
                name: "ix_supplies_supplier_id_supply_date",
                table: "supplies",
                columns: new[] { "supplier_id", "supply_date" });

            migrationBuilder.CreateIndex(
                name: "ix_supplies_updated_at",
                table: "supplies",
                column: "updated_at");

            migrationBuilder.CreateIndex(
                name: "ix_supply_lines_grade_id",
                table: "supply_lines",
                column: "grade_id");

            migrationBuilder.CreateIndex(
                name: "ix_supply_lines_material_id",
                table: "supply_lines",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_supply_lines_supply_id",
                table: "supply_lines",
                column: "supply_id");

            migrationBuilder.CreateIndex(
                name: "ix_supply_lines_unit_id",
                table: "supply_lines",
                column: "unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_units_code",
                table: "units",
                column: "code",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "app_settings");

            migrationBuilder.DropTable(
                name: "customer_interests");

            migrationBuilder.DropTable(
                name: "interactions");

            migrationBuilder.DropTable(
                name: "material_aliases");

            migrationBuilder.DropTable(
                name: "order_lines");

            migrationBuilder.DropTable(
                name: "order_stage_changes");

            migrationBuilder.DropTable(
                name: "party_phones");

            migrationBuilder.DropTable(
                name: "price_quotes");

            migrationBuilder.DropTable(
                name: "supply_lines");

            migrationBuilder.DropTable(
                name: "orders");

            migrationBuilder.DropTable(
                name: "supplier_products");

            migrationBuilder.DropTable(
                name: "supplies");

            migrationBuilder.DropTable(
                name: "units");

            migrationBuilder.DropTable(
                name: "grades");

            migrationBuilder.DropTable(
                name: "parties");

            migrationBuilder.DropTable(
                name: "materials");

            migrationBuilder.DropTable(
                name: "lookup_items");

            migrationBuilder.DropTable(
                name: "representatives");
        }
    }
}
