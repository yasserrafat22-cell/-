using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Qadisiyah.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AccessRulesRecordDate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateOnly>(
                name: "record_date",
                table: "parties",
                type: "date",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "record_date",
                table: "parties");
        }
    }
}
