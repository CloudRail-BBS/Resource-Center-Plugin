import RelayRoomsPage from "../../components/relay-rooms-page";

// App route templates read the payload as `@controller.model` — verified
// against core (templates/about.gjs does `<AboutPage @model={{@controller.model}} />`).
export default <template>
  <RelayRoomsPage @controller={{@controller}} />
</template>;
