using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Qadisiyah.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class ImportAndCompletion : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "name_missing",
                table: "parties",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<Guid>(
                name: "pending_grade_id",
                table: "parties",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "import_batches",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    kind = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    file_sha256 = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    summary = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_import_batches", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "ix_parties_pending_grade_id",
                table: "parties",
                column: "pending_grade_id");

            migrationBuilder.CreateIndex(
                name: "ix_import_batches_created_at",
                table: "import_batches",
                column: "created_at");

            migrationBuilder.AddForeignKey(
                name: "fk_parties_grades_pending_grade_id",
                table: "parties",
                column: "pending_grade_id",
                principalTable: "grades",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_parties_grades_pending_grade_id",
                table: "parties");

            migrationBuilder.DropTable(
                name: "import_batches");

            migrationBuilder.DropIndex(
                name: "ix_parties_pending_grade_id",
                table: "parties");

            migrationBuilder.DropColumn(
                name: "name_missing",
                table: "parties");

            migrationBuilder.DropColumn(
                name: "pending_grade_id",
                table: "parties");
        }
    }
}
