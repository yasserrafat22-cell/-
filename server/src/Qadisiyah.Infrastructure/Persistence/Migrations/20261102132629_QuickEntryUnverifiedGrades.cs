using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Qadisiyah.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class QuickEntryUnverifiedGrades : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "unverified_grade",
                table: "supplier_products",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "unverified_manufacturer",
                table: "supplier_products",
                type: "character varying(120)",
                maxLength: 120,
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "awaiting_promotion",
                table: "import_entries",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "error_code",
                table: "import_entries",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "origin_text",
                table: "import_entries",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "review_acknowledged",
                table: "import_entries",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "unverified_grade",
                table: "customer_interests",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "unverified_manufacturer",
                table: "customer_interests",
                type: "character varying(120)",
                maxLength: 120,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "unverified_grade",
                table: "supplier_products");

            migrationBuilder.DropColumn(
                name: "unverified_manufacturer",
                table: "supplier_products");

            migrationBuilder.DropColumn(
                name: "awaiting_promotion",
                table: "import_entries");

            migrationBuilder.DropColumn(
                name: "error_code",
                table: "import_entries");

            migrationBuilder.DropColumn(
                name: "origin_text",
                table: "import_entries");

            migrationBuilder.DropColumn(
                name: "review_acknowledged",
                table: "import_entries");

            migrationBuilder.DropColumn(
                name: "unverified_grade",
                table: "customer_interests");

            migrationBuilder.DropColumn(
                name: "unverified_manufacturer",
                table: "customer_interests");
        }
    }
}
