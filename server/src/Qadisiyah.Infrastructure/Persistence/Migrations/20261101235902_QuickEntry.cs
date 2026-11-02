using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Qadisiyah.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class QuickEntry : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "audience",
                table: "import_batches",
                type: "character varying(16)",
                maxLength: 16,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "created_count",
                table: "import_batches",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "duplicate_count",
                table: "import_batches",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "failed_count",
                table: "import_batches",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "file_name",
                table: "import_batches",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "method",
                table: "import_batches",
                type: "character varying(16)",
                maxLength: 16,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "pending_count",
                table: "import_batches",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "row_count",
                table: "import_batches",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "status",
                table: "import_batches",
                type: "character varying(24)",
                maxLength: 24,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "import_entries",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    batch_id = table.Column<Guid>(type: "uuid", nullable: false),
                    row_number = table.Column<int>(type: "integer", nullable: false),
                    kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true),
                    name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    phone = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    material_text = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    grade_text = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    manufacturer_text = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: true),
                    material_id = table.Column<Guid>(type: "uuid", nullable: true),
                    grade_id = table.Column<Guid>(type: "uuid", nullable: true),
                    status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    party_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_party = table.Column<bool>(type: "boolean", nullable: false),
                    duplicate_of_id = table.Column<Guid>(type: "uuid", nullable: true),
                    note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    created_by = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_import_entries", x => x.id);
                    table.ForeignKey(
                        name: "fk_import_entries_grades_grade_id",
                        column: x => x.grade_id,
                        principalTable: "grades",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_import_entries_import_batches_batch_id",
                        column: x => x.batch_id,
                        principalTable: "import_batches",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_import_entries_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_import_entries_batch_id",
                table: "import_entries",
                column: "batch_id");

            migrationBuilder.CreateIndex(
                name: "ix_import_entries_grade_id",
                table: "import_entries",
                column: "grade_id");

            migrationBuilder.CreateIndex(
                name: "ix_import_entries_material_id",
                table: "import_entries",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_import_entries_party_id",
                table: "import_entries",
                column: "party_id");

            migrationBuilder.CreateIndex(
                name: "ix_import_entries_status_created_by",
                table: "import_entries",
                columns: new[] { "status", "created_by" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "import_entries");

            migrationBuilder.DropColumn(
                name: "audience",
                table: "import_batches");

            migrationBuilder.DropColumn(
                name: "created_count",
                table: "import_batches");

            migrationBuilder.DropColumn(
                name: "duplicate_count",
                table: "import_batches");

            migrationBuilder.DropColumn(
                name: "failed_count",
                table: "import_batches");

            migrationBuilder.DropColumn(
                name: "file_name",
                table: "import_batches");

            migrationBuilder.DropColumn(
                name: "method",
                table: "import_batches");

            migrationBuilder.DropColumn(
                name: "pending_count",
                table: "import_batches");

            migrationBuilder.DropColumn(
                name: "row_count",
                table: "import_batches");

            migrationBuilder.DropColumn(
                name: "status",
                table: "import_batches");
        }
    }
}
