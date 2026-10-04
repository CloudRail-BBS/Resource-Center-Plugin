// Parent route of the `relay-rooms` namespace. Its template MUST render
// {{outlet}}, or the child route has nowhere to render and the page stays blank
// even though every route resolved.
//
// It imports nothing on purpose: the payload lives on the `index` child route,
// which renders the page component.
export default <template>
  <div class="relay-rooms-route">{{outlet}}</div>
</template>;
