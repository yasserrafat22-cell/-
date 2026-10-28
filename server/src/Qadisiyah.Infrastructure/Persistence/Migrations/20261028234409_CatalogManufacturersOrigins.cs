using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Qadisiyah.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class CatalogManufacturersOrigins : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_grades_material_id_normalized_code",
                table: "grades");

            migrationBuilder.AddColumn<Guid>(
                name: "origin_country_id",
                table: "supply_lines",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "origin_country_id",
                table: "supplier_products",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "open_spec",
                table: "order_lines",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<Guid>(
                name: "origin_country_id",
                table: "order_lines",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "created_at",
                table: "grades",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "created_by",
                table: "grades",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "is_verified",
                table: "grades",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<Guid>(
                name: "manufacturer_id",
                table: "grades",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "open_spec",
                table: "customer_interests",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<Guid>(
                name: "origin_country_id",
                table: "customer_interests",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "grade_origins",
                columns: table => new
                {
                    grade_id = table.Column<Guid>(type: "uuid", nullable: false),
                    country_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_grade_origins", x => new { x.grade_id, x.country_id });
                    table.ForeignKey(
                        name: "fk_grade_origins_grades_grade_id",
                        column: x => x.grade_id,
                        principalTable: "grades",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_grade_origins_lookup_items_country_id",
                        column: x => x.country_id,
                        principalTable: "lookup_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "manufacturers",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    normalized_name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_manufacturers", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "ix_supply_lines_origin_country_id",
                table: "supply_lines",
                column: "origin_country_id");

            migrationBuilder.CreateIndex(
                name: "ix_supplier_products_origin_country_id",
                table: "supplier_products",
                column: "origin_country_id");

            migrationBuilder.CreateIndex(
                name: "ix_order_lines_origin_country_id",
                table: "order_lines",
                column: "origin_country_id");

            migrationBuilder.CreateIndex(
                name: "ix_grades_manufacturer_id",
                table: "grades",
                column: "manufacturer_id");

            migrationBuilder.CreateIndex(
                name: "ix_grades_normalized_code",
                table: "grades",
                column: "normalized_code");

            migrationBuilder.CreateIndex(
                name: "ux_grades_material_manufacturer_code",
                table: "grades",
                columns: new[] { "material_id", "manufacturer_id", "normalized_code" },
                unique: true)
                .Annotation("Npgsql:NullsDistinct", false);

            migrationBuilder.CreateIndex(
                name: "ix_customer_interests_origin_country_id",
                table: "customer_interests",
                column: "origin_country_id");

            migrationBuilder.CreateIndex(
                name: "ix_grade_origins_country_id",
                table: "grade_origins",
                column: "country_id");

            migrationBuilder.CreateIndex(
                name: "ix_manufacturers_normalized_name",
                table: "manufacturers",
                column: "normalized_name",
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "fk_customer_interests_lookup_items_origin_country_id",
                table: "customer_interests",
                column: "origin_country_id",
                principalTable: "lookup_items",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "fk_grades_manufacturers_manufacturer_id",
                table: "grades",
                column: "manufacturer_id",
                principalTable: "manufacturers",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "fk_order_lines_lookup_items_origin_country_id",
                table: "order_lines",
                column: "origin_country_id",
                principalTable: "lookup_items",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "fk_supplier_products_lookup_items_origin_country_id",
                table: "supplier_products",
                column: "origin_country_id",
                principalTable: "lookup_items",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "fk_supply_lines_lookup_items_origin_country_id",
                table: "supply_lines",
                column: "origin_country_id",
                principalTable: "lookup_items",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_customer_interests_lookup_items_origin_country_id",
                table: "customer_interests");

            migrationBuilder.DropForeignKey(
                name: "fk_grades_manufacturers_manufacturer_id",
                table: "grades");

            migrationBuilder.DropForeignKey(
                name: "fk_order_lines_lookup_items_origin_country_id",
                table: "order_lines");

            migrationBuilder.DropForeignKey(
                name: "fk_supplier_products_lookup_items_origin_country_id",
                table: "supplier_products");

            migrationBuilder.DropForeignKey(
                name: "fk_supply_lines_lookup_items_origin_country_id",
                table: "supply_lines");

            migrationBuilder.DropTable(
                name: "grade_origins");

            migrationBuilder.DropTable(
                name: "manufacturers");

            migrationBuilder.DropIndex(
                name: "ix_supply_lines_origin_country_id",
                table: "supply_lines");

            migrationBuilder.DropIndex(
                name: "ix_supplier_products_origin_country_id",
                table: "supplier_products");

            migrationBuilder.DropIndex(
                name: "ix_order_lines_origin_country_id",
                table: "order_lines");

            migrationBuilder.DropIndex(
                name: "ix_grades_manufacturer_id",
                table: "grades");

            migrationBuilder.DropIndex(
                name: "ix_grades_normalized_code",
                table: "grades");

            migrationBuilder.DropIndex(
                name: "ux_grades_material_manufacturer_code",
                table: "grades");

            migrationBuilder.DropIndex(
                name: "ix_customer_interests_origin_country_id",
                table: "customer_interests");

            migrationBuilder.DropColumn(
                name: "origin_country_id",
                table: "supply_lines");

            migrationBuilder.DropColumn(
                name: "origin_country_id",
                table: "supplier_products");

            migrationBuilder.DropColumn(
                name: "open_spec",
                table: "order_lines");

            migrationBuilder.DropColumn(
                name: "origin_country_id",
                table: "order_lines");

            migrationBuilder.DropColumn(
                name: "created_at",
                table: "grades");

            migrationBuilder.DropColumn(
                name: "created_by",
                table: "grades");

            migrationBuilder.DropColumn(
                name: "is_verified",
                table: "grades");

            migrationBuilder.DropColumn(
                name: "manufacturer_id",
                table: "grades");

            migrationBuilder.DropColumn(
                name: "open_spec",
                table: "customer_interests");

            migrationBuilder.DropColumn(
                name: "origin_country_id",
                table: "customer_interests");

            migrationBuilder.CreateIndex(
                name: "ix_grades_material_id_normalized_code",
                table: "grades",
                columns: new[] { "material_id", "normalized_code" },
                unique: true);
        }
    }
}
