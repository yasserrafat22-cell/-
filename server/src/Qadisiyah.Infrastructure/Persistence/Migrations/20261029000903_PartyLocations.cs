using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Qadisiyah.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class PartyLocations : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "loading_location_id",
                table: "supplies",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "delivery_location_id",
                table: "orders",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "party_locations",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    party_id = table.Column<Guid>(type: "uuid", nullable: false),
                    kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    label = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    address_line = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    maps_url = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    latitude = table.Column<double>(type: "double precision", nullable: true),
                    longitude = table.Column<double>(type: "double precision", nullable: true),
                    access_notes = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    is_default = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_party_locations", x => x.id);
                    table.ForeignKey(
                        name: "fk_party_locations_parties_party_id",
                        column: x => x.party_id,
                        principalTable: "parties",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_supplies_loading_location_id",
                table: "supplies",
                column: "loading_location_id");

            migrationBuilder.CreateIndex(
                name: "ix_orders_delivery_location_id",
                table: "orders",
                column: "delivery_location_id");

            migrationBuilder.CreateIndex(
                name: "ix_party_locations_party_id",
                table: "party_locations",
                column: "party_id");

            migrationBuilder.CreateIndex(
                name: "ix_party_locations_updated_at",
                table: "party_locations",
                column: "updated_at");

            migrationBuilder.CreateIndex(
                name: "ux_party_locations_default",
                table: "party_locations",
                column: "party_id",
                unique: true,
                filter: "is_default AND deleted_at IS NULL");

            migrationBuilder.AddForeignKey(
                name: "fk_orders_party_locations_delivery_location_id",
                table: "orders",
                column: "delivery_location_id",
                principalTable: "party_locations",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "fk_supplies_party_locations_loading_location_id",
                table: "supplies",
                column: "loading_location_id",
                principalTable: "party_locations",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_orders_party_locations_delivery_location_id",
                table: "orders");

            migrationBuilder.DropForeignKey(
                name: "fk_supplies_party_locations_loading_location_id",
                table: "supplies");

            migrationBuilder.DropTable(
                name: "party_locations");

            migrationBuilder.DropIndex(
                name: "ix_supplies_loading_location_id",
                table: "supplies");

            migrationBuilder.DropIndex(
                name: "ix_orders_delivery_location_id",
                table: "orders");

            migrationBuilder.DropColumn(
                name: "loading_location_id",
                table: "supplies");

            migrationBuilder.DropColumn(
                name: "delivery_location_id",
                table: "orders");
        }
    }
}
