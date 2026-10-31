using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Qadisiyah.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class CustomerRegistration : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "governorate_id",
                table: "party_locations",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "region",
                table: "party_locations",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "number",
                table: "parties",
                type: "bigint",
                nullable: false)
                .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn);

            migrationBuilder.CreateIndex(
                name: "ix_party_locations_governorate_id",
                table: "party_locations",
                column: "governorate_id");

            migrationBuilder.CreateIndex(
                name: "ix_parties_number",
                table: "parties",
                column: "number",
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "fk_party_locations_lookup_items_governorate_id",
                table: "party_locations",
                column: "governorate_id",
                principalTable: "lookup_items",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_party_locations_lookup_items_governorate_id",
                table: "party_locations");

            migrationBuilder.DropIndex(
                name: "ix_party_locations_governorate_id",
                table: "party_locations");

            migrationBuilder.DropIndex(
                name: "ix_parties_number",
                table: "parties");

            migrationBuilder.DropColumn(
                name: "governorate_id",
                table: "party_locations");

            migrationBuilder.DropColumn(
                name: "region",
                table: "party_locations");

            migrationBuilder.DropColumn(
                name: "number",
                table: "parties");
        }
    }
}
