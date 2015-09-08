
function(doc, meta) {
    if(doc.type === "edge") {
        emit(meta.id, null);
    }
}
